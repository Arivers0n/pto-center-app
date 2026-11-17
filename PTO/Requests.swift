import SwiftUI

// MARK: - Разделы и цеха — те же, что в веб-версии

struct ReqSection: Identifiable, Hashable { let id: String; let name: String; let full: String }

extension Store {
    var reqSections: [ReqSection] {
        let l = cfg["reqSecs"].arr.compactMap { s -> ReqSection? in
            let id = s["id"].str
            guard !id.isEmpty else { return nil }
            return ReqSection(id: id, name: s["name"].str, full: s["full"].str.isEmpty ? s["name"].str : s["full"].str)
        }
        if !l.isEmpty { return l }
        return [("1", "Аппаратный"), ("2", "Сырный"), ("3", "ОВ 1"), ("4", "Сырный · ОВ 2"), ("5", "ПТ"), ("6", "Аппаратный · ОВ 2")]
            .map { ReqSection(id: $0.0, name: $0.1, full: $0.1) }
    }
    var shops: [String] {
        let l = cfg["shops"].arr.map(\.str).filter { !$0.isEmpty }
        return l.isEmpty ? ["Аппаратный цех", "Сырный цех"] : l
    }
    func secName(_ id: String) -> String { reqSections.first { $0.id == id }?.name ?? id }
}

let reqStatuses = ["Заявка", "Заказано", "Поставлено"]

private func statusColor(_ s: String) -> Color { s == "Поставлено" ? .green : s == "Заказано" ? .orange : .secondary }
private func reqTitle(_ v: JSON) -> String { v["label"].str.isEmpty ? v["no"].str : v["label"].str }

// MARK: - Список заявок

struct RequestsView: View {
    @EnvironmentObject var store: Store
    @State private var sec = "all"
    @State private var query = ""
    @State private var newReq: Rec?
    @State private var toDelete: Rec?

    static func blank(_ store: Store, sec: String?) -> Rec {
        let s = sec ?? store.reqSections.first?.id ?? ""
        let same = store.list("requests").filter { $0["sec"].str == s }
        let last = same.max { ($0["date"].str, $0["no"].num ?? 0) < ($1["date"].str, $1["no"].num ?? 0) }
        let no = Int(same.compactMap { $0["no"].num }.max() ?? 0) + 1
        var v: [String: JSON] = ["no": .n(Double(no)), "date": .s(Fmt.today), "sec": .s(s), "st": .s("Заявка"),
                                 "items": .a([.o(["name": .s(""), "unit": .s("шт"), "qty": .s(""), "purpose": .s(""), "note": .s("")])])]
        for k in ["shop", "work", "code", "place", "contract", "sign"] { if let x = last?[k] { v[k] = x } }
        if v["shop"] == nil { v["shop"] = .s(store.shops.first ?? "") }
        return Rec(id: Fmt.uid(), v: .o(v))
    }

    private var list: [Rec] {
        let q = query.lowercased().trimmingCharacters(in: .whitespaces)
        return store.list("requests")
            .filter { sec == "all" || $0["sec"].str == sec }
            .filter { r in
                q.isEmpty || ([r["no"].str, r["label"].str, r["work"].str, r["place"].str] + r["items"].arr.map { $0["name"].str })
                    .joined(separator: " ").lowercased().contains(q)
            }
            .sorted { ($0["date"].str, $0["no"].num ?? 0) > ($1["date"].str, $1["no"].num ?? 0) }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(list) { r in
                    NavigationLink(value: r.id) { RequestRow(r: r) }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) { toDelete = r } label: { Label("Удалить", systemImage: "trash") }
                        }
                        .swipeActions(edge: .leading) {
                            Button { newReq = copy(r) } label: { Label("Копия", systemImage: "plus.square.on.square") }.tint(.pto)
                        }
                }
                if list.isEmpty {
                    EmptyNote(title: query.isEmpty ? "Заявок нет" : "Ничего не найдено",
                              text: query.isEmpty ? "Нажмите «+», чтобы создать заявку." : "Попробуйте другое слово: номер, материал или цех.")
                }
            }
            .listStyle(.plain)
            .safeAreaInset(edge: .top, spacing: 0) { sectionBar }
            .searchable(text: $query, prompt: "Номер, материал, цех")
            .navigationTitle("Заявки на ТМЦ")
            .navigationDestination(for: String.self) { id in
                if let r = store.get("requests", id) { RequestEditView(rec: r, isNew: false) } else { Text("Заявка удалена") }
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { newReq = Self.blank(store, sec: sec == "all" ? nil : sec) } label: { Image(systemName: "plus") }
                        .accessibilityLabel("Новая заявка")
                }
            }
            .sheet(item: $newReq) { r in NavigationStack { RequestEditView(rec: r, isNew: true) } }
            .confirmationDialog("Удалить заявку?", isPresented: Binding(get: { toDelete != nil }, set: { if !$0 { toDelete = nil } }),
                                titleVisibility: .visible, presenting: toDelete) { r in
                Button("Удалить № \(reqTitle(r.v))", role: .destructive) { withAnimation { store.delete("requests", r.id) } }
            }
            .refreshable { await store.sync() }
        }
    }

    private var sectionBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Chip(title: "Все", count: store.list("requests").count, on: sec == "all") { sec = "all" }
                ForEach(store.reqSections) { s in
                    Chip(title: s.name, count: store.list("requests").filter { $0["sec"].str == s.id }.count, on: sec == s.id) { sec = s.id }
                }
            }
            .padding(.horizontal).padding(.vertical, 8)
        }
        .background(.bar)
    }

    private func copy(_ r: Rec) -> Rec {
        var n = Self.blank(store, sec: r["sec"].str)
        n.v["items"] = .a(r["items"].arr.map { i -> JSON in var x = i; x["got"] = nil; return x })
        return n
    }
}

struct Chip: View {
    let title: String
    var count: Int? = nil
    let on: Bool
    let tap: () -> Void
    var body: some View {
        Button(action: { withAnimation(.easeOut(duration: 0.2)) { tap() } }) {
            HStack(spacing: 5) {
                Text(title)
                if let count { Text("\(count)").foregroundStyle(on ? Color.white.opacity(0.8) : Color.secondary).monospacedDigit() }
            }
            .font(.subheadline.weight(on ? .semibold : .regular))
            .padding(.horizontal, 12).padding(.vertical, 7)
            .background(on ? Color.pto : Color(.secondarySystemBackground), in: Capsule())
            .foregroundStyle(on ? Color.white : Color.primary)
        }
        .buttonStyle(Pressable())
    }
}

struct EmptyNote: View {
    let title: String, text: String
    var body: some View {
        VStack(spacing: 6) {
            Text(title).font(.headline)
            Text(text).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 40).listRowSeparator(.hidden)
    }
}

struct RequestRow: View {
    @EnvironmentObject var store: Store
    let r: Rec
    var body: some View {
        let items = r["items"].arr.filter { !$0["name"].str.isEmpty }
        let st = r["st"].str.isEmpty ? "Заявка" : r["st"].str
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline) {
                Text("№ " + reqTitle(r.v)).font(.headline)
                Text(Fmt.show(r["date"].str)).font(.subheadline).foregroundStyle(.secondary)
                Spacer()
                Badge(text: st, color: statusColor(st))
            }
            Text(items.prefix(3).map { $0["name"].str }.joined(separator: " · ")).font(.subheadline).lineLimit(2)
            HStack(spacing: 8) {
                if !r["sec"].str.isEmpty { Badge(text: store.secName(r["sec"].str), color: .pto) }
                Text("\(items.count) поз.").font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Заявка: просмотр и правка

struct RequestEditView: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    let rec: Rec
    let isNew: Bool
    @State private var v: JSON = .o([:])
    @State private var items: [JSON] = []
    @State private var loaded = false
    @FocusState private var focus: Int?

    var body: some View {
        Form {
            Section("Заявка") {
                HStack {
                    Text("Номер")
                    TextField("№", text: str("no")).keyboardType(.numbersAndPunctuation).multilineTextAlignment(.trailing)
                }
                DatePicker("Дата", selection: date("date"), displayedComponents: .date)
                Picker("Раздел", selection: str("sec")) {
                    ForEach(store.reqSections) { Text($0.name).tag($0.id) }
                    if !store.reqSections.contains(where: { $0.id == v["sec"].str }) { Text(v["sec"].str.isEmpty ? "—" : v["sec"].str).tag(v["sec"].str) }
                }
                Picker("Цех / объект", selection: str("shop")) {
                    ForEach(store.shops, id: \.self) { Text($0).tag($0) }
                    if !store.shops.contains(v["shop"].str) { Text(v["shop"].str.isEmpty ? "—" : v["shop"].str).tag(v["shop"].str) }
                }
                TextField("Вид работ: для производства работ …", text: str("work"), axis: .vertical)
                TextField("Шифр проекта", text: str("code"))
            }
            Section("Поставка") {
                Picker("Статус", selection: Binding(get: { v["st"].str.isEmpty ? "Заявка" : v["st"].str }, set: { v["st"] = .s($0) })) {
                    ForEach(reqStatuses, id: \.self) { Text($0).tag($0) }
                }
                .pickerStyle(.segmented)
                if v["st"].str == "Заказано" {
                    DatePicker("Ожидаем к", selection: date("eta"), displayedComponents: .date)
                }
            }
            Section {
                ForEach(items.indices, id: \.self) { i in itemRow(i) }
                    .onDelete { items.remove(atOffsets: $0) }
                    .onMove { items.move(fromOffsets: $0, toOffset: $1) }
                Button {
                    withAnimation { items.append(.o(["name": .s(""), "unit": .s(items.last?["unit"].str ?? "шт"), "qty": .s(""), "purpose": .s(""), "note": .s("")])) }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { focus = items.count - 1 }
                } label: { Label("Добавить позицию", systemImage: "plus.circle.fill") }
            } header: {
                Text("Позиции · \(items.filter { !$0["name"].str.isEmpty }.count)")
            } footer: {
                Text("Смахните строку влево, чтобы удалить. «Получено» — сколько уже пришло на объект.")
            }
        }
        .environment(\.locale, Locale(identifier: "ru_RU"))
        .navigationTitle(isNew ? "Новая заявка" : "Заявка № " + reqTitle(v))
        .navigationBarTitleDisplayMode(.inline)
        .scrollDismissesKeyboard(.interactively)
        .toolbar {
            if isNew {
                ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Сохранить") { commit(); dismiss() }.disabled(!hasContent) }
            } else {
                ToolbarItem(placement: .primaryAction) {
                    ShareLink(item: shareText) { Image(systemName: "square.and.arrow.up") }.accessibilityLabel("Отправить списком")
                }
            }
            ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("Готово") { focus = nil } }
        }
        .onAppear { if !loaded { v = rec.v; items = rec["items"].arr; loaded = true } }
        .onDisappear { if !isNew { commit() } }
        .interactiveDismissDisabled(isNew && hasContent)
    }

    private var hasContent: Bool { items.contains { !$0["name"].str.trimmingCharacters(in: .whitespaces).isEmpty } }

    @ViewBuilder private func itemRow(_ i: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Наименование материала", text: itemStr(i, "name"), axis: .vertical)
                .font(.body.weight(.medium)).focused($focus, equals: i)
            HStack(spacing: 10) {
                TextField("Кол-во", text: itemStr(i, "qty")).keyboardType(.decimalPad).frame(maxWidth: 90)
                    .padding(6).background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 8))
                TextField("ед.", text: itemStr(i, "unit")).frame(maxWidth: 60)
                    .padding(6).background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 8))
                Spacer(minLength: 4)
                Text("получено").font(.caption).foregroundStyle(.secondary)
                TextField("—", text: itemStr(i, "got")).keyboardType(.decimalPad).frame(maxWidth: 64).multilineTextAlignment(.trailing)
                    .padding(6).background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 8))
            }
            .font(.subheadline)
        }
        .padding(.vertical, 2)
    }

    private var shareText: String {
        var t = "Заявка № \(reqTitle(v)) от \(Fmt.show(v["date"].str))\n"
        if !v["work"].str.isEmpty { t += "для производства работ \(v["work"].str), \(v["shop"].str)\n" }
        for (n, i) in items.filter({ !$0["name"].str.isEmpty }).enumerated() { t += "\(n + 1). \(i["name"].str) — \(i["qty"].str) \(i["unit"].str)\n" }
        return t
    }

    private func commit() {
        guard loaded else { return }
        if isNew && !hasContent { return }
        var out = v
        out["items"] = .a(items.filter { !$0["name"].str.trimmingCharacters(in: .whitespaces).isEmpty }.map(normalize))
        if out != rec.v { store.put("requests", Rec(id: rec.id, v: out)) }
    }
    private func normalize(_ i: JSON) -> JSON {
        var x = i
        for k in ["qty", "got"] {
            let s = x[k].str.trimmingCharacters(in: .whitespaces)
            if let d = Double(s.replacingOccurrences(of: ",", with: ".")) { x[k] = .n(d) } else if s.isEmpty && k == "got" { x[k] = nil }
        }
        return x
    }

    // привязки к полям записи
    private func str(_ k: String) -> Binding<String> {
        Binding(get: { v[k].str }, set: { new in
            if k == "no", let d = Double(new) { v[k] = .n(d); if v["label"] != nil { v["label"] = .s(new) } } else { v[k] = .s(new) }
        })
    }
    private func date(_ k: String) -> Binding<Date> { Binding(get: { Fmt.date(v[k].str) ?? Date() }, set: { v[k] = .s(Fmt.iso.string(from: $0)) }) }
    private func itemStr(_ i: Int, _ k: String) -> Binding<String> {
        Binding(get: { i < items.count ? items[i][k].str : "" }, set: { if i < items.count { items[i][k] = .s($0) } })
    }
}
