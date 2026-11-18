import SwiftUI
import PDFKit

// MARK: - Чертёж: родной просмотр PDF, замечания прямо на листе

struct NewPin: Equatable { let page: Int; let x: Double; let y: Double }

struct SchemeViewer: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var hSize
    let schemeID: String
    @State private var which = "pdf"
    @State private var url: URL?
    @State private var err: String?
    @State private var pinMode = false
    @State private var newPin: NewPin?
    @State private var pinText = ""
    @State private var showPins = false
    @State private var showSide = true
    @State private var focusPin: String?

    private var s: Rec? { store.get("schemes", schemeID) }
    private var openCount: Int { s?["pins"].arr.filter { !ksPinDone($0) }.count ?? 0 }
    private var regular: Bool { hSize == .regular }

    var body: some View {
        HStack(spacing: 0) {
            canvas
            if regular && showSide {
                Divider()
                KsSchemePanel(schemeID: schemeID, show: { id in focus(id) }, onDeleted: { dismiss() })
                    .frame(width: 340)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: showSide)
        .navigationTitle(s?["title"].str ?? "Схема")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                if s?["pdf"].str.isEmpty == false && s?["signed"].str.isEmpty == false {
                    Picker("Файл", selection: $which) { Text("Чистовик").tag("pdf"); Text("Подписанная").tag("signed") }
                        .pickerStyle(.segmented).frame(width: 240)
                }
            }
            ToolbarItemGroup(placement: .bottomBar) { bottomItems }
        }
        .toolbar(.visible, for: .bottomBar)
        .task(id: which) { await load() }
        .alert("Замечание на схеме", isPresented: Binding(get: { newPin != nil }, set: { if !$0 { newPin = nil } })) {
            TextField("Что не так", text: $pinText)
            Button("Отмена", role: .cancel) { newPin = nil }
            Button("Добавить") { addPin() }
        }
        .sheet(isPresented: $showPins) {
            PinsList(schemeID: schemeID, show: { id in showPins = false; focus(id) }, onDeleted: { dismiss() })
        }
        .onAppear { if s?["pdf"].str.isEmpty != false { which = "signed" } }
    }

    private var canvas: some View {
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
    }

    @ViewBuilder private var bottomItems: some View {
        Menu {
            ForEach(["draft", "review", "signed"], id: \.self) { k in
                Button { setStatus(k) } label: {
                    if s?["status"].str == k { Label(isStatus[k]?.0 ?? k, systemImage: "checkmark") } else { Text(isStatus[k]?.0 ?? k) }
                }
            }
        } label: { Label(isStatus[s?["status"].str ?? "draft"]?.0 ?? "Статус", systemImage: "checkmark.seal") }
        Spacer()
        Button {
            if regular { showSide.toggle() } else { showPins = true }
        } label: { Label(openCount > 0 ? "Замечания · \(openCount)" : "Замечания", systemImage: regular ? "sidebar.right" : "list.bullet") }
        Button { pinMode.toggle() } label: { Label("Замечание", systemImage: pinMode ? "mappin.slash" : "mappin.and.ellipse") }
        if let url { ShareLink(item: url) { Label("Поделиться", systemImage: "square.and.arrow.up") } }
    }

    private func focus(_ id: String) {
        focusPin = nil
        DispatchQueue.main.async { focusPin = id }
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

/// Поле, которое пишет в запись только когда закончили ввод (не на каждую букву)
struct KsCommitField: View {
    let title: String
    let initial: String
    var vertical = false
    let commit: (String) -> Void
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        TextField(title, text: $text, axis: vertical ? .vertical : .horizontal)
            .focused($focused)
            .onAppear { text = initial }
            .onChange(of: focused) { f in if !f { commit(text) } }
            .onSubmit { commit(text) }
            .onDisappear { commit(text) }
    }
}

private struct KsPin: Identifiable {
    let index: Int
    let json: JSON
    var id: String { json["id"].str.isEmpty ? "i\(index)" : json["id"].str }
}

/// Боковая панель схемы: сведения, замечания, строки КС. На iPad стоит рядом с чертежом, на iPhone открывается листом
struct KsSchemePanel: View {
    @EnvironmentObject var store: Store
    let schemeID: String
    let show: (String) -> Void
    let onDeleted: () -> Void
    @State private var confirmDelete = false

    private var scheme: Rec? { store.get("schemes", schemeID) }

    var body: some View {
        List {
            if let s = scheme {
                infoSection(s)
                pinsSection(s)
                ksSection(s)
                filesSection(s)
                Section {
                    Button(role: .destructive) { confirmDelete = true } label: { Label("Удалить схему", systemImage: "trash") }
                }
            } else {
                EmptyNote(title: "Схема не найдена", text: "Возможно, её удалили на другом устройстве.")
            }
        }
        .listStyle(.insetGrouped)
        .ptoScreen()
        .confirmationDialog("Удалить схему вместе с замечаниями?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Удалить", role: .destructive) { store.delete("schemes", schemeID); onDeleted() }
            Button("Отмена", role: .cancel) {}
        }
    }

    // MARK: сведения

    private func infoSection(_ s: Rec) -> some View {
        let closings = store.list("closings").sorted { ($0["shop"].str, $0["no"].num ?? 0) < ($1["shop"].str, $1["no"].num ?? 0) }
        return Section("Сведения") {
            Picker("Статус", selection: Binding(get: { s["status"].str.isEmpty ? "draft" : s["status"].str }, set: { set("status", .s($0)) })) {
                ForEach(["draft", "review", "signed"], id: \.self) { Text(isStatus[$0]?.0 ?? $0).tag($0) }
            }
            Picker("Закрытие", selection: Binding(get: { s["closing"].str }, set: { move(to: $0) })) {
                Text("Не распределены").tag("")
                ForEach(closings) { c in Text((c["shop"].str.isEmpty ? "" : c["shop"].str + " · ") + ksClosingName(c)).tag(c.id) }
            }
            KsCommitField(title: "Название", initial: s["title"].str, vertical: true) { set("title", .s($0)) }
            KsCommitField(title: "Системы через запятую", initial: s["sys"].arr.map { $0.str }.joined(separator: ", ")) { t in
                let parts = t.split(whereSeparator: { $0 == "," || $0 == ";" }).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                set("sys", .a(parts.map { JSON.s($0) }))
            }
            KsCommitField(title: "Оси", initial: s["axes"].str) { set("axes", .s($0)) }
            KsCommitField(title: "Заметка: что доделать, кому отдать на подпись", initial: s["note"].str, vertical: true) { set("note", .s($0)) }
        }
    }

    private func set(_ key: String, _ v: JSON) {
        guard var x = scheme, x.v[key] != v else { return }
        x.v[key] = v
        store.put("schemes", x)
    }

    private func move(to closingID: String) {
        guard var x = scheme else { return }
        x.v["closing"] = closingID.isEmpty ? JSON.null : JSON.s(closingID)
        if let c = store.get("closings", closingID), !c["shop"].str.isEmpty { x.v["shop"] = c["shop"] ?? .s("") }
        store.put("schemes", x)
    }

    // MARK: замечания

    private func pinsSection(_ s: Rec) -> some View {
        let pins = s["pins"].arr.enumerated().map { KsPin(index: $0.offset, json: $0.element) }
        let open = pins.filter { !ksPinDone($0.json) }.count
        return Section {
            if pins.isEmpty {
                Text("Нажмите «Замечание» и коснитесь места на чертеже — появится метка с номером.").font(.subheadline).foregroundStyle(.secondary)
            }
            ForEach(pins) { p in pinRow(p) }
        } header: {
            Text(open > 0 ? "Замечания · открыто \(open)" : "Замечания")
        }
    }

    private func pinRow(_ p: KsPin) -> some View {
        let done = ksPinDone(p.json)
        return HStack(alignment: .top, spacing: 10) {
            Button { show(p.json["id"].str) } label: {
                Text("\(p.index + 1)").font(.caption.weight(.bold)).foregroundStyle(.white).monospacedDigit()
                    .frame(width: 28, height: 28).background(done ? Color.green : Color.orange, in: Circle())
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Показать замечание \(p.index + 1) на чертеже")
            VStack(alignment: .leading, spacing: 3) {
                KsCommitField(title: "Что не так в этом месте", initial: p.json["text"].str, vertical: true) { updatePin(p.index, "text", .s($0)) }
                    .strikethrough(done)
                Text("лист \(Int(p.json["pg"].num ?? 1)) · \(Fmt.show(p.json["date"].str))" + (p.json["on"].str == "signed" ? " · на подписанной" : ""))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Button { updatePin(p.index, "done", .b(!done)) } label: {
                Image(systemName: done ? "checkmark.circle.fill" : "circle").font(.title3).foregroundStyle(done ? Color.green : Color.secondary)
                    .frame(minWidth: 32, minHeight: 32)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(done ? "Вернуть в открытые" : "Отметить устранённым")
        }
        .swipeActions { Button(role: .destructive) { removePin(p.index) } label: { Label("Удалить", systemImage: "trash") } }
    }

    private func updatePin(_ i: Int, _ key: String, _ v: JSON) {
        guard var x = scheme else { return }
        var pins = x["pins"].arr
        guard i < pins.count, pins[i][key] != v else { return }
        pins[i][key] = v
        x.v["pins"] = .a(pins)
        store.put("schemes", x)
    }

    private func removePin(_ i: Int) {
        guard var x = scheme else { return }
        var pins = x["pins"].arr
        guard i < pins.count else { return }
        pins.remove(at: i)
        x.v["pins"] = .a(pins)
        store.put("schemes", x)
    }

    // MARK: КС и файлы

    @ViewBuilder private func ksSection(_ s: Rec) -> some View {
        if let c = store.get("closings", s["closing"].str) {
            let lines = (c["ks"]?["lines"]).arr.enumerated().filter { $0.element["schemes"].arr.contains { $0.str == s.id } }
            Section("В КС-2 закрытия №\(c["no"].str)") {
                if lines.isEmpty {
                    Text("Схема не привязана ни к одной строке КС-2.").font(.subheadline).foregroundStyle(.secondary)
                }
                ForEach(lines, id: \.offset) { item in
                    let l = item.element
                    Text("Строка \(item.offset + 1): \(l["name"].str) — \(l["qty"].str) \(l["unit"].str)").font(.subheadline)
                }
            }
        }
    }

    @ViewBuilder private func filesSection(_ s: Rec) -> some View {
        let dwg = s["dwg"].arr.map { $0.str }
        if !s["pdfName"].str.isEmpty || !s["sigName"].str.isEmpty || !dwg.isEmpty {
            Section("Файлы") {
                if !s["pdfName"].str.isEmpty { Text("Схема: " + s["pdfName"].str).font(.footnote) }
                if !s["sigName"].str.isEmpty { Text("Подписанная: " + s["sigName"].str).font(.footnote) }
                ForEach(dwg, id: \.self) { Text("DWG: " + $0).font(.caption).foregroundStyle(.secondary).lineLimit(2) }
            }
        }
    }
}

/// Панель для iPhone: лист с замечаниями и сведениями
struct PinsList: View {
    @Environment(\.dismiss) private var dismiss
    let schemeID: String
    let show: (String) -> Void
    var onDeleted: () -> Void = {}

    var body: some View {
        NavigationStack {
            KsSchemePanel(schemeID: schemeID, show: show, onDeleted: { dismiss(); onDeleted() })
                .navigationTitle("Замечания и сведения").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Готово") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
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
        let sig = pins.map { $0["id"].str + ($0["done"]?.bool == true ? "1" : "0") + $0["text"].str }.joined(separator: ",")
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
                let col: UIColor = ksPinDone(p) ? .systemGreen : .systemOrange
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
