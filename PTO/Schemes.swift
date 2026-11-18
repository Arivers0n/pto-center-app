import SwiftUI

let clStatus: [String: (String, Color)] = ["work": ("В работе", .orange), "closed": ("Закрыто", .green), "rest": ("Остатки", .secondary)]
let isStatus: [String: (String, Color)] = ["draft": ("Черновик", .secondary), "review": ("На подписи", .orange), "signed": ("Подписана", .green)]
private let isStatusOrder = ["draft", "review", "signed"]

struct SchemeRoute: Hashable { let id: String }

// MARK: - Проекты (цехи) и общие мелочи

func ksShort(_ s: String) -> String {
    s.replacingOccurrences(of: "\\s+цех$", with: "", options: [.regularExpression, .caseInsensitive]).trimmingCharacters(in: .whitespaces)
}
func ksShopsFull(_ cfg: JSON) -> [String] {
    let l = (cfg["shops"]).arr.map { $0.str }.filter { !$0.isEmpty }
    return l.isEmpty ? ["Аппаратный цех", "Сырный цех"] : l
}
func ksProjects(_ cfg: JSON) -> [String] {
    var seen = Set<String>()
    return ksShopsFull(cfg).map(ksShort).filter { !$0.isEmpty && seen.insert($0).inserted }
}
func ksProjectFull(_ cfg: JSON, _ short: String) -> String {
    ksShopsFull(cfg).first { ksShort($0) == short } ?? short
}
func ksClosingName(_ c: Rec) -> String {
    "Закрытие № \(c["no"].str)" + (c["date"].str.isEmpty ? "" : " от \(Fmt.show(c["date"].str))")
}
func ksPinDone(_ p: JSON) -> Bool { p["done"]?.bool ?? false }

extension View {
    /// Широкие экраны не растягиваем: колонка до 760 pt по центру
    func ksColumn() -> some View {
        self.frame(maxWidth: 760).frame(maxWidth: .infinity)
    }
}

private enum KsSchemesSheet: Identifiable {
    case new, edit(String), actualize
    var id: String {
        switch self {
        case .new: return "new"
        case .edit(let i): return "edit-" + i
        case .actualize: return "actualize"
        }
    }
}

// MARK: - Закрытия по проектам

struct SchemesView: View {
    @EnvironmentObject var store: Store
    @State private var shop = "Все"
    @State private var query = ""
    @State private var sys: String?
    @State private var sheet: KsSchemesSheet?
    @State private var addProject = false
    @State private var projectName = ""
    @State private var deleteClosing: Rec?
    @State private var deleteScheme: Rec?
    @State private var driveBusy = false
    @State private var driveNote: String?

    private var projects: [String] {
        let used = store.list("closings").map { $0["shop"].str }.filter { !$0.isEmpty }
        var seen = Set<String>()
        return (ksProjects(store.cfg) + used).filter { seen.insert($0).inserted }
    }
    private func inShop(_ r: Rec) -> Bool { shop == "Все" || r["shop"].str == shop }
    private var closings: [Rec] {
        store.list("closings").filter(inShop).sorted { a, b in
            if a["shop"].str != b["shop"].str { return a["shop"].str < b["shop"].str }
            return (a["no"].num ?? 0) > (b["no"].num ?? 0)
        }
    }
    private var searching: Bool { !query.trimmingCharacters(in: .whitespaces).isEmpty || sys != nil }
    private var shopSchemes: [Rec] { store.list("schemes").filter(inShop) }
    private var allSys: [String] { Array(Set(shopSchemes.flatMap { $0["sys"].arr.map { $0.str } })).sorted() }
    private var found: [Rec] {
        let q = query.lowercased().trimmingCharacters(in: .whitespaces)
        return shopSchemes.filter { (s: Rec) -> Bool in
            if let sys, !s["sys"].arr.map({ $0.str }).contains(sys) { return false }
            if q.isEmpty { return true }
            var p = [s["title"].str, s["axes"].str, s["group"].str, s["note"].str]
            p += s["sys"].arr.map { $0.str }
            p += s["pins"].arr.map { $0["text"].str }
            return p.joined(separator: " ").lowercased().contains(q)
        }
        .sorted { $0["title"].str.localizedStandardCompare($1["title"].str) == .orderedAscending }
    }

    var body: some View {
        List {
            if searching { searchRows } else { closingRows }
        }
        .listStyle(.insetGrouped)
        .ksColumn().ptoScreen()
        .safeAreaInset(edge: .top, spacing: 0) { projectBar }
        .searchable(text: $query, prompt: "Система, оси, помещение, замечание")
        .navigationTitle("Исполнительные схемы")
        .navigationDestination(for: String.self) { id in ClosingView(closingID: id) }
        .navigationDestination(for: SchemeRoute.self) { r in SchemeViewer(schemeID: r.id) }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button { sheet = .new } label: { Image(systemName: "plus") }.accessibilityLabel("Новое закрытие")
                Menu {
                    Button { Task { await syncDrive() } } label: { Label("Из Google Диска", systemImage: "externaldrive.badge.icloud") }
                    Button { sheet = .actualize } label: { Label("Актуализировать", systemImage: "arrow.triangle.2.circlepath") }
                } label: { Image(systemName: "ellipsis.circle") }
                .accessibilityLabel("Ещё")
            }
        }
        .overlay(alignment: .bottom) {
            if driveBusy {
                HStack(spacing: 8) { ProgressView(); Text("Читаю Google Диск…").font(.subheadline) }
                    .padding(.horizontal, 16).padding(.vertical, 10).background(.ultraThinMaterial, in: Capsule()).padding(.bottom, 16)
            }
        }
        .sheet(item: $sheet) { s in
            switch s {
            case .new: KsClosingEditor(closingID: nil, defaultShop: shop)
            case .edit(let id): KsClosingEditor(closingID: id, defaultShop: shop)
            case .actualize: KsActualizeSheet()
            }
        }
        .alert("Новый проект", isPresented: $addProject) {
            TextField("Например: Корпус 3", text: $projectName)
            Button("Добавить") { addProjectNow() }
            Button("Отмена", role: .cancel) { projectName = "" }
        } message: { Text("Цех, корпус или объект. Появится вкладкой и в списках проектов.") }
        .alert("Google Диск", isPresented: Binding(get: { driveNote != nil }, set: { if !$0 { driveNote = nil } })) {
            Button("Понятно", role: .cancel) {}
        } message: { Text(driveNote ?? "") }
        .confirmationDialog("Удалить закрытие? Его схемы перейдут в «Не распределены».", isPresented: Binding(get: { deleteClosing != nil }, set: { if !$0 { deleteClosing = nil } }), titleVisibility: .visible) {
            Button("Удалить закрытие", role: .destructive) { if let c = deleteClosing { ksDeleteClosing(store, c.id) } }
            Button("Отмена", role: .cancel) {}
        }
        .confirmationDialog("Удалить схему?", isPresented: Binding(get: { deleteScheme != nil }, set: { if !$0 { deleteScheme = nil } }), titleVisibility: .visible) {
            Button("Удалить схему", role: .destructive) { if let s = deleteScheme { withAnimation { store.delete("schemes", s.id) } } }
            Button("Отмена", role: .cancel) {}
        }
        .refreshable { await store.sync() }
    }

    // MARK: части экрана

    private var projectBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Chip(title: "Все", on: shop == "Все") { shop = "Все" }
                ForEach(projects, id: \.self) { s in Chip(title: s, on: shop == s) { shop = s } }
                Chip(title: "+ Проект", on: false) { projectName = ""; addProject = true }
            }
            .padding(.horizontal).padding(.vertical, 8)
        }
        .background(.bar)
    }

    @ViewBuilder private var closingRows: some View {
        let none = shopSchemes.filter { $0["closing"].str.isEmpty }
        Section {
            ForEach(closings) { c in
                NavigationLink(value: c.id) { ClosingRow(c: c) }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) { deleteClosing = c } label: { Label("Удалить", systemImage: "trash") }
                        Button { sheet = .edit(c.id) } label: { Label("Изменить", systemImage: "pencil") }.tint(.blue)
                    }
                    .contextMenu {
                        Button { sheet = .edit(c.id) } label: { Label("Изменить", systemImage: "pencil") }
                        Button(role: .destructive) { deleteClosing = c } label: { Label("Удалить", systemImage: "trash") }
                    }
            }
            if !none.isEmpty {
                NavigationLink(value: "none") { Label("Не распределены · \(none.count)", systemImage: "tray") }
            }
        }
        if closings.isEmpty && none.isEmpty {
            EmptyNote(title: "Закрытий пока нет", text: "Нажмите «+», чтобы создать закрытие, или заберите схемы из Google Диска через меню «…».")
        }
    }

    @ViewBuilder private var searchRows: some View {
        if !allSys.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    Chip(title: "Все системы", on: sys == nil) { sys = nil }
                    ForEach(allSys, id: \.self) { s in Chip(title: s, on: sys == s) { sys = (sys == s ? nil : s) } }
                }
            }
            .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12)).listRowBackground(Color.clear)
        }
        Section("Найдено: \(found.count)") {
            ForEach(found) { s in
                NavigationLink(value: SchemeRoute(id: s.id)) { SchemeRow(s: s, showClosing: true) { deleteScheme = $0 } }
            }
        }
        if found.isEmpty { EmptyNote(title: "Ничего не найдено", text: "Ищите по системе, осям, помещению или тексту замечания.") }
    }

    // MARK: действия

    private func addProjectNow() {
        let name = projectName.trimmingCharacters(in: .whitespacesAndNewlines)
        projectName = ""
        guard !name.isEmpty else { return }
        var list = ksShopsFull(store.cfg)
        guard !list.contains(where: { ksShort($0).lowercased() == ksShort(name).lowercased() }) else { shop = ksShort(name); return }
        list.append(name)
        var c = store.cfg
        c["shops"] = JSON.a(list.map { JSON.s($0) })
        store.setKV("cfg", c)
        shop = ksShort(name)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    private func syncDrive() async {
        driveBusy = true
        defer { driveBusy = false }
        do { driveNote = try await KsDrive.sync(store: store).message } catch { driveNote = error.localizedDescription }
    }
}

/// Удаление закрытия: схемы остаются, но без закрытия
func ksDeleteClosing(_ store: Store, _ id: String) {
    for s in store.list("schemes") where s["closing"].str == id {
        var x = s
        x.v["closing"] = JSON.null
        store.put("schemes", x)
    }
    store.delete("closings", id)
}

private struct KsActualizeSheet: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            ActualizeView()
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Закрыть") { dismiss() } } }
        }
    }
}

struct ClosingRow: View {
    @EnvironmentObject var store: Store
    let c: Rec
    var body: some View {
        let s = store.list("schemes").filter { $0["closing"].str == c.id }
        let signed = s.filter { $0["status"].str == "signed" }.count
        let pins = s.reduce(0) { $0 + $1["pins"].arr.filter { !ksPinDone($0) }.count }
        let st = clStatus[c["status"].str] ?? ("В работе", Color.orange)
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("№ \(c["no"].str)").font(.headline)
                Text(c["shop"].str).foregroundStyle(.secondary)
                Spacer()
                Badge(text: st.0, color: st.1)
            }
            ProgressView(value: Double(signed), total: Double(max(1, s.count))).tint(.green)
            Text((c["date"].str.isEmpty ? "без даты" : "КС от \(Fmt.show(c["date"].str))") + " · подписано \(signed) из \(s.count)" + (pins > 0 ? " · замечаний \(pins)" : ""))
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Создание и правка закрытия

struct KsClosingEditor: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    let closingID: String?
    let defaultShop: String
    var onDeleted: () -> Void = {}
    @State private var no = ""
    @State private var date = ""
    @State private var shop = ""
    @State private var status = "work"
    @State private var note = ""
    @State private var error: String?
    @State private var confirmDelete = false
    @State private var ready = false

    private var shopOptions: [String] {
        var l = ksProjects(store.cfg)
        if !shop.isEmpty && !l.contains(shop) { l.append(shop) }
        return l
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Номер закрытия", text: $no).keyboardType(.numberPad)
                    KsDateRow(title: "Дата КС", text: $date)
                    Picker("Проект", selection: $shop) { ForEach(shopOptions, id: \.self) { Text($0).tag($0) } }
                    Picker("Статус", selection: $status) {
                        ForEach(["work", "closed", "rest"], id: \.self) { Text(clStatus[$0]?.0 ?? $0).tag($0) }
                    }
                }
                Section("Заметка: что не забыть к закрытию") {
                    TextField("Заметка", text: $note, axis: .vertical).lineLimit(3...8)
                }
                if let error { Section { Text(error).foregroundStyle(.red) } }
                if closingID != nil {
                    Section { Button(role: .destructive) { confirmDelete = true } label: { Label("Удалить закрытие", systemImage: "trash") } }
                }
            }
            .navigationTitle(closingID == nil ? "Новое закрытие" : "Закрытие")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Сохранить") { save() } }
            }
            .confirmationDialog("Удалить закрытие? Его схемы перейдут в «Не распределены».", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Удалить", role: .destructive) {
                    if let id = closingID { ksDeleteClosing(store, id) }
                    dismiss(); onDeleted()
                }
                Button("Отмена", role: .cancel) {}
            }
            .onAppear(perform: load)
        }
    }

    private func load() {
        guard !ready else { return }
        ready = true
        if let id = closingID, let c = store.get("closings", id) {
            no = c["no"].str; date = c["date"].str; shop = c["shop"].str
            status = c["status"].str.isEmpty ? "work" : c["status"].str; note = c["note"].str
        } else {
            shop = defaultShop != "Все" ? defaultShop : (ksProjects(store.cfg).first ?? "")
            let top = store.list("closings").filter { $0["shop"].str == shop }.map { Int($0["no"].num ?? 0) }.max() ?? 0
            no = String(top + 1)
        }
    }

    private func save() {
        guard let n = Int(no.trimmingCharacters(in: .whitespaces)), n > 0 else { error = "Укажите номер закрытия"; return }
        let clash = store.list("closings").contains { $0.id != closingID && Int($0["no"].num ?? 0) == n && $0["shop"].str == shop }
        guard !clash else { error = "Закрытие №\(n) в этом проекте уже есть"; return }
        var r = closingID.flatMap { store.get("closings", $0) } ?? Rec(id: Fmt.uid(), v: .o([:]))
        r.v["no"] = JSON.n(Double(n))
        r.v["date"] = JSON.s(date)
        r.v["shop"] = JSON.s(shop)
        r.v["status"] = JSON.s(status)
        r.v["note"] = JSON.s(note)
        store.put("closings", r)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        dismiss()
    }
}

// MARK: - Схемы одного закрытия

private enum KsClosingTab { case schemes, ks }

struct ClosingView: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    let closingID: String
    @State private var tab = KsClosingTab.schemes
    @State private var sys: String?
    @State private var loading = false
    @State private var progress = 0.0
    @State private var note: String?
    @State private var showEdit = false
    @State private var deleteScheme: Rec?

    private var closing: Rec? { store.get("closings", closingID) }
    private var own: [Rec] { store.list("schemes").filter { closingID == "none" ? $0["closing"].str.isEmpty : $0["closing"].str == closingID } }
    private var schemes: [Rec] {
        own.filter { s in sys.map { s["sys"].arr.map { $0.str }.contains($0) } ?? true }
            .sorted { $0["title"].str.localizedStandardCompare($1["title"].str) == .orderedAscending }
    }
    private var allSys: [String] { Array(Set(own.flatMap { $0["sys"].arr.map { $0.str } })).sorted() }
    private var files: [String] { schemes.flatMap { [$0["pdf"].str, $0["signed"].str] }.filter { $0.hasPrefix("gd:") } }
    private var ksLabel: String {
        let t = closing.map(ksSavedTotal) ?? 0
        return t > 0 ? "КС-2 и КС-3 · \(Fmt.num(t, 0)) ₽" : "КС-2 и КС-3"
    }

    var body: some View {
        VStack(spacing: 0) {
            if closing != nil {
                Picker("Раздел", selection: $tab) {
                    Text("Схемы · \(own.count)").tag(KsClosingTab.schemes)
                    Text(ksLabel).tag(KsClosingTab.ks)
                }
                .pickerStyle(.segmented).padding(.horizontal).padding(.vertical, 8)
            }
            if tab == .ks && closing != nil { KSView(closingID: closingID) } else { schemesList }
        }
        .ksColumn().ptoScreen()
        .navigationTitle(closing.map(ksClosingName) ?? "Не распределены")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                if let c = closing {
                    KsCSVShare(title: "Опись в Excel", fileName: "Опись_" + ksClosingName(c) + ".csv", rows: inventory())
                    Button { showEdit = true } label: { Image(systemName: "pencil") }.accessibilityLabel("Изменить закрытие")
                }
            }
        }
        .sheet(isPresented: $showEdit) { KsClosingEditor(closingID: closingID, defaultShop: "Все") { dismiss() } }
        .confirmationDialog("Удалить схему?", isPresented: Binding(get: { deleteScheme != nil }, set: { if !$0 { deleteScheme = nil } }), titleVisibility: .visible) {
            Button("Удалить схему", role: .destructive) { if let s = deleteScheme { withAnimation { store.delete("schemes", s.id) } } }
            Button("Отмена", role: .cancel) {}
        }
    }

    private var schemesList: some View {
        List {
            if let c = closing {
                Section {
                    Picker("Статус", selection: Binding(get: { c["status"].str.isEmpty ? "work" : c["status"].str }, set: { new in
                        var x = c; x.v["status"] = JSON.s(new); store.put("closings", x)
                    })) {
                        ForEach(["work", "closed", "rest"], id: \.self) { k in Text(clStatus[k]?.0 ?? k).tag(k) }
                    }
                    .pickerStyle(.segmented)
                    if !c["note"].str.isEmpty { Text(c["note"].str).font(.subheadline).foregroundStyle(.secondary) }
                    downloadRow
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
                ForEach(schemes) { s in
                    NavigationLink(value: SchemeRoute(id: s.id)) { SchemeRow(s: s, showClosing: false) { deleteScheme = $0 } }
                }
                if schemes.isEmpty { EmptyNote(title: "Схем нет", text: "Перенесите схему сюда из другого закрытия (долгое нажатие на строку) или заберите схемы из Google Диска.") }
            }
        }
        .listStyle(.insetGrouped)
        .ptoScreen()
    }

    @ViewBuilder private var downloadRow: some View {
        if closing != nil {
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
        }
    }

    private func inventory() -> [[String]] {
        var rows = [["№", "Схема", "Группа", "Системы", "Оси", "Статус", "Открытых замечаний", "Файл схемы", "Подписанная копия"]]
        for (i, s) in schemes.enumerated() {
            let open = s["pins"].arr.filter { !ksPinDone($0) }.count
            rows.append([String(i + 1), s["title"].str, s["group"].str, s["sys"].arr.map { $0.str }.joined(separator: ", "), s["axes"].str,
                         isStatus[s["status"].str]?.0 ?? isStatus["draft"]!.0, String(open), s["pdfName"].str, s["sigName"].str])
        }
        return rows
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

// MARK: - Строка схемы: статус, перенос в другое закрытие

struct SchemeRow: View {
    @EnvironmentObject var store: Store
    let s: Rec
    let showClosing: Bool
    var onDelete: (Rec) -> Void = { _ in }

    private var targets: [Rec] {
        store.list("closings").filter { $0.id != s["closing"].str }.sorted { a, b in
            if a["shop"].str != b["shop"].str { return a["shop"].str < b["shop"].str }
            return (a["no"].num ?? 0) > (b["no"].num ?? 0)
        }
    }

    var body: some View {
        let st = isStatus[s["status"].str] ?? ("Черновик", Color.secondary)
        let open = s["pins"].arr.filter { !ksPinDone($0) }.count
        let local = [s["pdf"].str, s["signed"].str].contains { !$0.isEmpty && FileCache.has($0) }
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(s["title"].str).font(.subheadline.weight(.semibold)).lineLimit(3)
                if local { Image(systemName: "arrow.down.circle.fill").font(.caption).foregroundStyle(.secondary).accessibilityLabel("Скачано на устройство") }
            }
            HStack(spacing: 6) {
                ForEach(s["sys"].arr.map { $0.str }, id: \.self) { Badge(text: $0, color: .pto) }
                if !s["axes"].str.isEmpty { Text(s["axes"].str).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                Spacer(minLength: 0)
                if open > 0 { Badge(text: "\(open) замеч.", color: .orange) }
                Badge(text: st.0, color: st.1)
            }
            if showClosing, let c = store.get("closings", s["closing"].str) {
                Text(ksClosingName(c) + " · " + c["shop"].str).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 3)
        .swipeActions(edge: .leading) {
            Button { cycleStatus() } label: { Label("Статус", systemImage: "checkmark.seal") }.tint(.green)
        }
        .contextMenu {
            Button { cycleStatus() } label: { Label("Следующий статус", systemImage: "checkmark.seal") }
            Menu {
                if !s["closing"].str.isEmpty { Button("Не распределены") { move(nil) } }
                ForEach(targets) { c in
                    Button((c["shop"].str.isEmpty ? "" : c["shop"].str + " · ") + ksClosingName(c)) { move(c) }
                }
            } label: { Label("Перенести в закрытие…", systemImage: "arrow.right.circle") }
            Button(role: .destructive) { onDelete(s) } label: { Label("Удалить схему", systemImage: "trash") }
        }
    }

    private func cycleStatus() {
        let cur = isStatusOrder.firstIndex(of: s["status"].str) ?? 0
        var x = s
        x.v["status"] = JSON.s(isStatusOrder[(cur + 1) % isStatusOrder.count])
        store.put("schemes", x)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private func move(_ c: Rec?) {
        var x = s
        x.v["closing"] = c.map { JSON.s($0.id) } ?? JSON.null
        if let c, !c["shop"].str.isEmpty { x.v["shop"] = JSON.s(c["shop"].str) }
        withAnimation { store.put("schemes", x) }
    }
}
