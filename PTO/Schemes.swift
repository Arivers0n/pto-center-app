import SwiftUI
import PDFKit

let clStatus: [String: (String, Color)] = ["work": ("В работе", .orange), "closed": ("Закрыто", .green), "rest": ("Остатки", .secondary)]
let isStatus: [String: (String, Color)] = ["draft": ("Черновик", .secondary), "review": ("На подписи", .orange), "signed": ("Подписана", .green)]

private func closingName(_ c: Rec) -> String {
    "Закрытие № \(c["no"].str)" + (c["date"].str.isEmpty ? "" : " от \(Fmt.show(c["date"].str))")
}
private func pinDone(_ p: JSON) -> Bool { p["done"]?.bool ?? false }

// MARK: - Закрытия по проектам

struct SchemesView: View {
    @EnvironmentObject var store: Store
    @State private var shop = "Все"
    @State private var query = ""

    private var shops: [String] {
        let s = store.shops.map { $0.replacingOccurrences(of: " цех", with: "") } + store.list("closings").map { $0["shop"].str }.filter { !$0.isEmpty }
        var seen = Set<String>()
        return s.filter { seen.insert($0).inserted }
    }
    private var closings: [Rec] {
        store.list("closings").filter { shop == "Все" || $0["shop"].str == shop }
            .sorted { ($0["shop"].str, -($0["no"].num ?? 0)) < ($1["shop"].str, -($1["no"].num ?? 0)) }
    }
    private var found: [Rec] {
        let q = query.lowercased()
        return store.list("schemes").filter { (s: Rec) -> Bool in
            var p = [s["title"].str, s["axes"].str, s["group"].str]
            p += s["sys"].arr.map { $0.str }
            p += s["pins"].arr.map { $0["text"].str }
            return p.joined(separator: " ").lowercased().contains(q)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                if query.isEmpty {
                    ForEach(closings) { c in NavigationLink(value: c.id) { ClosingRow(c: c) } }
                    let none = store.list("schemes").filter { $0["closing"].str.isEmpty }
                    if !none.isEmpty { NavigationLink(value: "none") { Label("Не распределены · \(none.count)", systemImage: "tray") } }
                    if closings.isEmpty { EmptyNote(title: "Закрытий нет", text: "Схемы появляются из Google Диска или из папки на компьютере в ПТО-центре.") }
                } else {
                    ForEach(found) { s in NavigationLink(value: SchemeRoute(id: s.id)) { SchemeRow(s: s, showClosing: true) } }
                    if found.isEmpty { EmptyNote(title: "Ничего не найдено", text: "Ищите по системе, осям, помещению или тексту замечания.") }
                }
            }
            .listStyle(.insetGrouped)
            .safeAreaInset(edge: .top, spacing: 0) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        Chip(title: "Все", on: shop == "Все") { shop = "Все" }
                        ForEach(shops, id: \.self) { s in Chip(title: s, on: shop == s) { shop = s } }
                    }
                    .padding(.horizontal).padding(.vertical, 8)
                }
                .background(.bar)
            }
            .searchable(text: $query, prompt: "Система, оси, помещение, замечание")
            .navigationTitle("Исполнительные схемы")
            .navigationDestination(for: String.self) { id in ClosingView(closingID: id) }
            .navigationDestination(for: SchemeRoute.self) { r in SchemeViewer(schemeID: r.id) }
            .refreshable { await store.sync() }
        }
    }
}

struct SchemeRoute: Hashable { let id: String }

struct ClosingRow: View {
    @EnvironmentObject var store: Store
    let c: Rec
    var body: some View {
        let s = store.list("schemes").filter { $0["closing"].str == c.id }
        let signed = s.filter { $0["status"].str == "signed" }.count
        let st = clStatus[c["status"].str] ?? ("В работе", Color.orange)
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("№ \(c["no"].str)").font(.headline)
                Text(c["shop"].str).foregroundStyle(.secondary)
                Spacer()
                Badge(text: st.0, color: st.1)
            }
            ProgressView(value: Double(signed), total: Double(max(1, s.count))).tint(.green)
            Text((c["date"].str.isEmpty ? "без даты" : "КС от \(Fmt.show(c["date"].str))") + " · подписано \(signed) из \(s.count)")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Схемы одного закрытия

struct ClosingView: View {
    @EnvironmentObject var store: Store
    let closingID: String
    @State private var sys: String?
    @State private var loading = false
    @State private var progress = 0.0
    @State private var note: String?

    private var closing: Rec? { store.get("closings", closingID) }
    private var schemes: [Rec] {
        store.list("schemes").filter { closingID == "none" ? $0["closing"].str.isEmpty : $0["closing"].str == closingID }
            .filter { s in sys.map { s["sys"].arr.map(\.str).contains($0) } ?? true }
            .sorted { $0["title"].str.localizedStandardCompare($1["title"].str) == .orderedAscending }
    }
    private var allSys: [String] {
        Array(Set(store.list("schemes").filter { $0["closing"].str == closingID }.flatMap { $0["sys"].arr.map(\.str) })).sorted()
    }
    private var files: [String] { schemes.flatMap { [$0["pdf"].str, $0["signed"].str] }.filter { $0.hasPrefix("gd:") } }

    var body: some View {
        List {
            if let c = closing {
                Section {
                    Picker("Статус", selection: Binding(get: { c["status"].str.isEmpty ? "work" : c["status"].str }, set: { new in
                        var x = c; x.v["status"] = .s(new); store.put("closings", x)
                    })) {
                        ForEach(["work", "closed", "rest"], id: \.self) { k in Text(clStatus[k]?.0 ?? k).tag(k) }
                    }
                    .pickerStyle(.segmented)
                    Button { Task { await download() } } label: {
                        HStack {
                            Label(loading ? "Скачиваю…" : "На это устройство", systemImage: "arrow.down.circle")
                            Spacer()
                            Text("\(files.filter { FileCache.has($0) }.count) из \(files.count)").foregroundStyle(.secondary).monospacedDigit()
                        }
                    }
                    .disabled(loading || files.isEmpty)
                    if loading { ProgressView(value: progress) }
                    if let note { Text(note).font(.footnote).foregroundStyle(.secondary) }
                } footer: { Text("Скачанные чертежи открываются сразу и без интернета.") }
            }
            if !allSys.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        Chip(title: "Все системы", on: sys == nil) { sys = nil }
                        ForEach(allSys, id: \.self) { s in Chip(title: s, on: sys == s) { sys = s } }
                    }
                }
                .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12)).listRowBackground(Color.clear)
            }
            Section("Схемы · \(schemes.count)") {
                ForEach(schemes) { s in NavigationLink(value: SchemeRoute(id: s.id)) { SchemeRow(s: s, showClosing: false) } }
            }
        }
        .navigationTitle(closing.map(closingName) ?? "Не распределены")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func download() async {
        loading = true; progress = 0; note = nil
        var ok = 0, fail = 0
        let list = files
        for (i, f) in list.enumerated() {
            do { _ = try await FileCache.get(f, token: store.token); ok += 1 } catch { fail += 1 }
            progress = Double(i + 1) / Double(max(1, list.count))
        }
        loading = false
        note = fail == 0 ? "Готово: \(ok) файлов на устройстве." : "Скачано \(ok), не удалось \(fail). Проверьте связь и повторите."
    }
}

struct SchemeRow: View {
    @EnvironmentObject var store: Store
    let s: Rec
    let showClosing: Bool
    var body: some View {
        let st = isStatus[s["status"].str] ?? ("Черновик", Color.secondary)
        let open = s["pins"].arr.filter { !pinDone($0) }.count
        VStack(alignment: .leading, spacing: 5) {
            Text(s["title"].str).font(.subheadline.weight(.semibold)).lineLimit(3)
            HStack(spacing: 6) {
                ForEach(s["sys"].arr.map(\.str), id: \.self) { Badge(text: $0, color: .pto) }
                if !s["axes"].str.isEmpty { Text(s["axes"].str).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                Spacer(minLength: 0)
                if open > 0 { Badge(text: "\(open) замеч.", color: .orange) }
                Badge(text: st.0, color: st.1)
            }
            if showClosing, let c = store.get("closings", s["closing"].str) {
                Text(closingName(c) + " · " + c["shop"].str).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 3)
    }
}

// MARK: - Чертёж: родной просмотр PDF, замечания прямо на листе

struct NewPin: Equatable { let page: Int; let x: Double; let y: Double }

struct SchemeViewer: View {
    @EnvironmentObject var store: Store
    let schemeID: String
    @State private var which = "pdf"
    @State private var url: URL?
    @State private var err: String?
    @State private var pinMode = false
    @State private var newPin: NewPin?
    @State private var pinText = ""
    @State private var showPins = false
    @State private var focusPin: String?

    private var s: Rec? { store.get("schemes", schemeID) }
    private var openCount: Int { s?["pins"].arr.filter { !pinDone($0) }.count ?? 0 }

    var body: some View {
        ZStack {
            Color(.secondarySystemBackground).ignoresSafeArea()
            if let url {
                PDFCanvas(url: url, pins: (s?["pins"].arr ?? []).filter { $0["on"].str.isEmpty || $0["on"].str == which }, pinMode: pinMode, focus: focusPin) { page, x, y in
                    newPin = NewPin(page: page, x: x, y: y); pinText = ""
                }
                .ignoresSafeArea(edges: .bottom)
                .transition(.opacity)
            } else if let err {
                VStack(spacing: 12) {
                    Image(systemName: "doc.questionmark").font(.largeTitle).foregroundStyle(.secondary)
                    Text(err).multilineTextAlignment(.center).foregroundStyle(.secondary)
                    Button("Повторить") { Task { await load() } }.buttonStyle(.bordered)
                }
                .padding(32)
            } else {
                ProgressView("Открываю чертёж…")
            }
            if pinMode {
                VStack {
                    Text("Коснитесь места на чертеже").font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 14).padding(.vertical, 8).background(.ultraThinMaterial, in: Capsule()).padding(.top, 8)
                    Spacer()
                }
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: url)
        .animation(.spring(response: 0.3), value: pinMode)
        .navigationTitle(s?["title"].str ?? "Схема")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                if s?["pdf"].str.isEmpty == false && s?["signed"].str.isEmpty == false {
                    Picker("Файл", selection: $which) { Text("Схема").tag("pdf"); Text("Подписанная").tag("signed") }
                        .pickerStyle(.segmented).frame(width: 220)
                }
            }
            ToolbarItemGroup(placement: .bottomBar) {
                Menu {
                    ForEach(["draft", "review", "signed"], id: \.self) { k in
                        Button { setStatus(k) } label: {
                            if s?["status"].str == k { Label(isStatus[k]?.0 ?? k, systemImage: "checkmark") } else { Text(isStatus[k]?.0 ?? k) }
                        }
                    }
                } label: { Label(isStatus[s?["status"].str ?? "draft"]?.0 ?? "Статус", systemImage: "checkmark.seal") }
                Spacer()
                Button { showPins = true } label: { Label(openCount > 0 ? "Замечания · \(openCount)" : "Замечания", systemImage: "list.bullet") }
                Button { pinMode.toggle() } label: { Label("Замечание", systemImage: pinMode ? "mappin.slash" : "mappin.and.ellipse") }
                if let url { ShareLink(item: url) { Label("Отправить", systemImage: "square.and.arrow.up") } }
            }
        }
        .toolbar(.visible, for: .bottomBar)
        .task(id: which) { await load() }
        .alert("Замечание на схеме", isPresented: Binding(get: { newPin != nil }, set: { if !$0 { newPin = nil } })) {
            TextField("Что не так", text: $pinText)
            Button("Отмена", role: .cancel) { newPin = nil }
            Button("Добавить") { addPin() }
        }
        .sheet(isPresented: $showPins) { PinsList(schemeID: schemeID) { id in showPins = false; focusPin = nil; DispatchQueue.main.async { focusPin = id } } }
        .onAppear { if s?["pdf"].str.isEmpty != false { which = "signed" } }
    }

    private func load() async {
        guard let s else { return }
        let id = which == "signed" ? s["signed"].str : s["pdf"].str
        url = nil; err = nil
        guard !id.isEmpty else { err = "Файла нет"; return }
        do { url = try await FileCache.get(id, token: store.token) } catch { err = error.localizedDescription }
    }
    private func setStatus(_ k: String) {
        guard var x = s else { return }
        x.v["status"] = .s(k); store.put("schemes", x)
    }
    private func addPin() {
        guard var x = s, let p = newPin, !pinText.trimmingCharacters(in: .whitespaces).isEmpty else { newPin = nil; return }
        let pin: JSON = .o(["id": .s(Fmt.uid()), "pg": .n(Double(p.page)), "x": .n(p.x), "y": .n(p.y), "text": .s(pinText),
                            "done": .b(false), "date": .s(Fmt.today), "on": .s(which)])
        x.v["pins"] = .a(x["pins"].arr + [pin]); store.put("schemes", x)
        newPin = nil; pinMode = false
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
}

struct PinsList: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    let schemeID: String
    let show: (String) -> Void
    var body: some View {
        NavigationStack {
            List {
                let pins = store.get("schemes", schemeID)?["pins"].arr ?? []
                if pins.isEmpty { EmptyNote(title: "Замечаний нет", text: "Нажмите «Замечание» и коснитесь места на чертеже.") }
                ForEach(Array(pins.enumerated()), id: \.offset) { i, p in
                    HStack(alignment: .top, spacing: 10) {
                        Button { toggle(i) } label: {
                            Image(systemName: pinDone(p) ? "checkmark.circle.fill" : "circle").font(.title3).foregroundStyle(pinDone(p) ? Color.green : Color.orange)
                        }
                        .buttonStyle(.plain)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(p["text"].str).strikethrough(pinDone(p))
                            Text("лист \(Int(p["pg"].num ?? 1)) · \(Fmt.show(p["date"].str))").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Показать") { show(p["id"].str) }.font(.caption).buttonStyle(.bordered)
                    }
                    .swipeActions { Button(role: .destructive) { remove(i) } label: { Label("Удалить", systemImage: "trash") } }
                }
            }
            .navigationTitle("Замечания").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Готово") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
    }
    private func toggle(_ i: Int) {
        guard var x = store.get("schemes", schemeID) else { return }
        var pins = x["pins"].arr
        guard i < pins.count else { return }
        pins[i]["done"] = .b(!pinDone(pins[i])); x.v["pins"] = .a(pins); store.put("schemes", x)
    }
    private func remove(_ i: Int) {
        guard var x = store.get("schemes", schemeID) else { return }
        var pins = x["pins"].arr
        guard i < pins.count else { return }
        pins.remove(at: i); x.v["pins"] = .a(pins); store.put("schemes", x)
    }
}

/// PDFKit: плавное масштабирование щипком, быстрая отрисовка больших чертежей, метки замечаний поверх листа
struct PDFCanvas: UIViewRepresentable {
    let url: URL
    let pins: [JSON]
    let pinMode: Bool
    let focus: String?
    let onPin: (Int, Double, Double) -> Void

    func makeCoordinator() -> Coord { Coord(onPin: onPin) }

    func makeUIView(context: Context) -> PDFView {
        let v = PDFView()
        v.autoScales = true
        v.displayMode = .singlePageContinuous
        v.displayDirection = .vertical
        v.backgroundColor = .secondarySystemBackground
        v.pageShadowsEnabled = true
        v.document = PDFDocument(url: url)
        v.maxScaleFactor = 12
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coord.tap(_:)))
        tap.delegate = context.coordinator
        v.addGestureRecognizer(tap)
        context.coordinator.view = v
        return v
    }

    func updateUIView(_ v: PDFView, context: Context) {
        if v.document?.documentURL != url { v.document = PDFDocument(url: url); v.autoScales = true; context.coordinator.drawn = "" }
        v.minScaleFactor = v.scaleFactorForSizeToFit * 0.5
        context.coordinator.onPin = onPin
        context.coordinator.pinMode = pinMode
        guard let doc = v.document else { return }
        // метки перерисовываются только когда замечания изменились
        let sig = pins.map { $0["id"].str + ($0["done"]?.bool == true ? "1" : "0") }.joined(separator: ",")
        if sig != context.coordinator.drawn {
            context.coordinator.drawn = sig
            for i in 0..<doc.pageCount {
                guard let page = doc.page(at: i) else { continue }
                page.annotations.filter { $0.userName == "pto-pin" }.forEach { page.removeAnnotation($0) }
            }
            for (n, p) in pins.enumerated() {
                guard let page = doc.page(at: max(0, Int(p["pg"].num ?? 1) - 1)) else { continue }
                let box = page.bounds(for: .cropBox)
                let x = box.minX + CGFloat(p["x"].num ?? 0) * box.width
                let y = box.maxY - CGFloat(p["y"].num ?? 0) * box.height
                let r: CGFloat = max(10, box.width / 90)
                let a = PDFAnnotation(bounds: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2), forType: .circle, withProperties: nil)
                let col: UIColor = pinDone(p) ? .systemGreen : .systemOrange
                a.color = col
                a.interiorColor = col.withAlphaComponent(0.35)
                let b = PDFBorder(); b.lineWidth = max(2, r / 5); a.border = b
                a.userName = "pto-pin"
                a.contents = "\(n + 1). " + p["text"].str
                page.addAnnotation(a)
            }
        }
        if let focus, focus != context.coordinator.lastFocus, let p = pins.first(where: { $0["id"].str == focus }),
           let page = doc.page(at: max(0, Int(p["pg"].num ?? 1) - 1)) {
            context.coordinator.lastFocus = focus
            let box = page.bounds(for: .cropBox)
            let x = box.minX + CGFloat(p["x"].num ?? 0) * box.width, y = box.maxY - CGFloat(p["y"].num ?? 0) * box.height
            v.go(to: CGRect(x: x - box.width / 6, y: y - box.height / 6, width: box.width / 3, height: box.height / 3), on: page)
        }
        if focus == nil { context.coordinator.lastFocus = nil }
    }

    final class Coord: NSObject, UIGestureRecognizerDelegate {
        var onPin: (Int, Double, Double) -> Void
        var pinMode = false
        var lastFocus: String?
        var drawn = ""
        weak var view: PDFView?
        init(onPin: @escaping (Int, Double, Double) -> Void) { self.onPin = onPin }
        func gestureRecognizer(_ g: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith o: UIGestureRecognizer) -> Bool { true }
        @objc func tap(_ g: UITapGestureRecognizer) {
            guard pinMode, let v = view, let doc = v.document else { return }
            let pt = g.location(in: v)
            guard let page = v.page(for: pt, nearest: true) else { return }
            let p = v.convert(pt, to: page)
            let box = page.bounds(for: .cropBox)
            let x = Double((p.x - box.minX) / box.width), y = Double((box.maxY - p.y) / box.height)
            guard (0...1).contains(x), (0...1).contains(y) else { return }
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            onPin(doc.index(for: page) + 1, x, y)
        }
    }
}
