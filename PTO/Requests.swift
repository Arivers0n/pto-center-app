import SwiftUI
import UniformTypeIdentifiers

// MARK: - Разделы и цеха — те же, что в веб-версии

struct ReqSection: Identifiable, Hashable { let id: String; let name: String; let full: String }

private let rqDefaultSections: [(String, String, String)] = [
    ("1", "Аппаратный", "Аппаратный цех (водоснабжение и канализация)"),
    ("2", "Сырный", "Сырный цех (водоснабжение и канализация)"),
    ("3", "ОВ 1", "ОВ 1"),
    ("4", "Сырный · ОВ 2", "Сырный цех, ОВ 2 (вентиляция)"),
    ("5", "ПТ", "ПТ (внутренний противопожарный водопровод)"),
    ("6", "Аппаратный · ОВ 2", "Аппаратный цех, ОВ 2 (вентиляция)")
]

extension Store {
    var reqSections: [ReqSection] {
        let l = cfg["reqSecs"].arr.compactMap { s -> ReqSection? in
            let id = s["id"].str
            guard !id.isEmpty else { return nil }
            return ReqSection(id: id, name: s["name"].str, full: s["full"].str.isEmpty ? s["name"].str : s["full"].str)
        }
        if !l.isEmpty { return l }
        return rqDefaultSections.map { ReqSection(id: $0.0, name: $0.1, full: $0.2) }
    }
    var shops: [String] {
        let l = cfg["shops"].arr.map(\.str).filter { !$0.isEmpty }
        return l.isEmpty ? ["Аппаратный цех", "Сырный цех"] : l
    }
    func secName(_ id: String) -> String { reqSections.first { $0.id == id }?.name ?? id }
}

let reqStatuses = ["Заявка", "Заказано", "Поставлено"]

struct RqRoute: Hashable { let id: String }

// MARK: - Общая логика заявок (как в веб-версии)

enum Rq {
    static func title(_ v: JSON) -> String { v["label"].str.isEmpty ? v["no"].str : v["label"].str }
    static func status(_ v: JSON) -> String { v["st"].str.isEmpty ? "Заявка" : v["st"].str }
    static func eta(_ v: JSON) -> String { String(v["eta"].str.prefix(10)) }

    static func isLate(_ v: JSON) -> Bool {
        let e = eta(v)
        return status(v) == "Заказано" && !e.isEmpty && e < Fmt.today
    }
    static func statusText(_ v: JSON) -> String {
        let e = eta(v)
        if isLate(v) { return "ждём с " + Fmt.show(e) }
        if status(v) == "Заказано" && !e.isEmpty { return "Заказано · к " + Fmt.show(e) }
        return status(v)
    }
    static func statusColor(_ v: JSON) -> Color {
        if isLate(v) { return .red }
        switch status(v) {
        case "Поставлено": return .green
        case "Заказано": return .orange
        default: return .secondary
        }
    }

    /// Сколько позиций получено полностью (как gotInfo в вебе)
    static func got(_ v: JSON) -> (full: Int, total: Int, tracked: Bool) {
        let items = v["items"].arr
        var tracked = false
        var full = 0
        for i in items {
            if let g = i["got"], g != .null, !g.str.isEmpty { tracked = true }
            let q = i["qty"].num ?? 0
            if (i["got"].num ?? 0) >= q && q > 0 { full += 1 }
        }
        return (full, items.count, tracked)
    }

    /// Назначение: готовое или собранное из «вид работ, цех, шифр»
    static func place(_ v: JSON) -> String {
        let p = v["place"].str
        if !p.isEmpty { return p }
        guard v["work"] != nil else { return "" }
        let w = v["work"].str
        var t = "для производства работ " + (w.isEmpty ? "…" : w)
        if !v["shop"].str.isEmpty { t += ", " + v["shop"].str }
        if !v["code"].str.isEmpty { t += ", " + v["code"].str }
        return t
    }

    static func contract(_ v: JSON, _ cfg: JSON) -> String { v["contract"] != nil ? v["contract"].str : cfg["contract"].str }

    static func order(_ a: Rec, _ b: Rec, byDate: Bool) -> Bool {
        let da = a["date"].str, db = b["date"].str
        if byDate && da != db { return da > db }
        let na = a["no"].num ?? 0, nb = b["no"].num ?? 0
        if na != nb { return na > nb }
        if da != db { return da > db }
        return a.id > b.id
    }

    static func newItem(_ cfg: JSON, unit: String = "шт") -> JSON {
        .o(["name": .s(""), "unit": .s(unit), "qty": .n(1), "purpose": .s(""), "cust": .s(cfg["receiverName"].str), "note": .s("")])
    }

    /// Новая заявка раздела: номер следующий, значения берутся из последней заявки раздела (newReq)
    static func blank(_ store: Store, sec: String?) -> Rec {
        let ids = store.reqSections.map(\.id)
        let s = sec ?? (ids.contains("2") ? "2" : (ids.first ?? "2"))
        let same = store.list("requests").filter { $0["sec"].str == s }
        let last = same.sorted { order($0, $1, byDate: true) }.first
        let no = Int(same.compactMap { $0["no"].num }.max() ?? 0) + 1
        let work: JSON = last?["work"] ?? .s("по сетям водоснабжения и канализации")
        var v: [String: JSON] = [
            "no": .n(Double(no)), "date": .s(Fmt.today), "sec": .s(s),
            "shop": .s(last?["shop"].str ?? store.shops.first ?? ""),
            "work": work,
            "code": .s(last?["code"].str ?? ""), "place": .s(last?["place"].str ?? ""),
            "items": .a([newItem(store.cfg)])
        ]
        if let c = last?["contract"] { v["contract"] = c }
        if let g = last?["sign"] { v["sign"] = g }
        return Rec(id: Fmt.uid(), v: .o(v))
    }

    /// Копия заявки (dupReq): новый номер в разделе, сегодняшняя дата, без метки
    static func copy(_ store: Store, _ r: Rec) -> Rec {
        let sec = r["sec"].str
        let same = store.list("requests").filter { $0["sec"].str == sec }
        let no = Int(same.compactMap { $0["no"].num }.max() ?? 0) + 1
        var n = Rec(id: Fmt.uid(), v: r.v)
        n.v["no"] = .n(Double(no))
        n.v["label"] = nil
        n.v["date"] = .s(Fmt.today)
        return n
    }

    // подписанты
    struct Signer: Hashable { var post: String; var name: String }

    static func signers(_ text: String) -> [Signer] {
        text.split(separator: "\n").compactMap { line -> Signer? in
            let p = line.split(separator: "|", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) }
            let post = p.first ?? ""
            let name = p.count > 1 ? p[1] : ""
            return post.isEmpty && name.isEmpty ? nil : Signer(post: post, name: name)
        }
    }
    static func issuers(_ cfg: JSON) -> [Signer] {
        let l = signers(cfg["issuersText"].str)
        return l.isEmpty ? [Signer(post: cfg["issuerPost"].str, name: cfg["issuerName"].str)] : l
    }
    static func receivers(_ cfg: JSON) -> [Signer] {
        let l = signers(cfg["receiversText"].str)
        return l.isEmpty ? [Signer(post: cfg["receiverPost"].str, name: cfg["receiverName"].str)] : l
    }

    /// Выдал/Получил: из заявки, иначе первые из настроек (reqSign)
    static func sign(_ v: JSON, _ cfg: JSON, issuer: Signer? = nil, receiver: Signer? = nil) -> (ip: String, iname: String, rp: String, rname: String) {
        let g: JSON = v["sign"] ?? .null
        let own = v["sign"] != nil
        let i: Signer = issuer ?? (own ? Signer(post: g["ip"].str, name: g["in"].str) : issuers(cfg)[0])
        let r: Signer = receiver ?? (own ? Signer(post: g["rp"].str, name: g["rn"].str) : receivers(cfg)[0])
        let company = cfg["company"].str
        return (i.post.isEmpty ? "Руководитель проекта" : i.post, i.name,
                r.post.isEmpty ? "Начальник участка " + company : r.post, r.name)
    }

    // нормализация названий (mkey, nm в вебе)
    static func mkey(_ s: String) -> String {
        let drop: Set<Character> = [" ", "\t", "\n", "\"", "'", "«", "»", ",", ".", ";", ":", "(", ")", "\\", "-"]
        var out = ""
        for ch in s.lowercased().replacingOccurrences(of: "ё", with: "е") where !drop.contains(ch) {
            if "х×x".contains(ch) { out.append("x") } else if "ф⌀ø".contains(ch) { out.append("ф") } else { out.append(ch) }
        }
        return out
    }
    static func nm(_ s: String) -> String {
        var out = ""
        var gap = false
        for ch in s.lowercased().replacingOccurrences(of: "ё", with: "е") {
            let ok = ("а"..."я").contains(ch) || ("a"..."z").contains(ch) || ("0"..."9").contains(ch)
            if ok {
                if gap && !out.isEmpty { out.append(" ") }
                gap = false
                out.append(ch)
            } else { gap = true }
        }
        return out
    }

    // CSV и текст
    static let bom = "\u{FEFF}"
    static func csvLine(_ cells: [String]) -> String {
        cells.map { "\"" + $0.replacingOccurrences(of: "\"", with: "\"\"") + "\"" }.joined(separator: ";")
    }
    static func csv(_ lines: [[String]]) -> String { bom + lines.map(csvLine).joined(separator: "\r\n") }

    static func listCSV(_ recs: [Rec], store: Store) -> String {
        var rows: [[String]] = [["№", "Дата", "Раздел", "Назначение", "Позиций", "Поставка", "М-15", "Пометка"]]
        for r in recs {
            rows.append([title(r.v), Fmt.show(r["date"].str), store.secName(r["sec"].str), place(r.v),
                         String(r["items"].arr.count), statusText(r.v), r["m15"].str, r["fnote"].str])
        }
        return csv(rows)
    }
    static func listText(_ recs: [Rec], store: Store) -> String {
        recs.map { r -> String in
            let n = r["items"].arr.count
            return "№ \(title(r.v)) от \(Fmt.show(r["date"].str)) · \(store.secName(r["sec"].str)) · \(n) поз. · \(statusText(r.v))"
        }.joined(separator: "\n")
    }
    static func itemsText(_ v: JSON) -> String {
        var t = "Заявка № \(title(v)) от \(Fmt.show(v["date"].str))\n\(place(v))\n"
        for (n, i) in v["items"].arr.filter({ !$0["name"].str.isEmpty }).enumerated() {
            t += "\(n + 1). \(i["name"].str) — \(i["qty"].str) \(i["unit"].str)\n"
        }
        return t
    }
}

// MARK: - Файлы для «Поделиться»

enum RqTemp {
    static func write(_ name: String, _ data: Data) throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("rq-share", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let bad = CharacterSet(charactersIn: "/\\:*?\"<>|")
        let safe = name.components(separatedBy: bad).joined(separator: "_")
        let url = dir.appendingPathComponent(safe)
        try data.write(to: url, options: .atomic)
        return url
    }
}

struct RqCSVFile: Transferable {
    let name: String
    let text: String
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .commaSeparatedText) { (f: RqCSVFile) -> SentTransferredFile in
            let url = try RqTemp.write(f.name, Data(f.text.utf8))
            return SentTransferredFile(url)
        }
    }
}

// MARK: - Список заявок

struct RequestsView: View {
    @EnvironmentObject private var theme: ThemeStore
    @EnvironmentObject var store: Store
    @Environment(\.horizontalSizeClass) private var hSize
    @State private var sec: String
    @State private var query: String
    @State private var newReq: Rec?
    @State private var toDelete: Rec?
    @State private var banner: String?
    @State private var showDash = false
    @State private var showAct = false

    init(initialSec: String = "all", initialQuery: String = "") {
        _sec = State(initialValue: initialSec)
        _query = State(initialValue: initialQuery)
    }

    static func blank(_ store: Store, sec: String?) -> Rec { Rq.blank(store, sec: sec) }

    private var list: [Rec] {
        let q = query.lowercased().trimmingCharacters(in: .whitespaces)
        let all = store.list("requests").filter { sec == "all" || $0["sec"].str == sec }
        let found = all.filter { (r: Rec) -> Bool in
            if q.isEmpty { return true }
            let head: [String] = [Rq.place(r.v), r["fnote"].str, r["no"].str, r["label"].str]
            let names: [String] = r["items"].arr.map { $0["name"].str }
            return (head + names).joined(separator: " ").lowercased().contains(q)
        }
        return found.sorted { Rq.order($0, $1, byDate: sec == "all") }
    }

    var body: some View {
        let rows = list
        List {
            ForEach(rows) { r in
                NavigationLink(value: RqRoute(id: r.id)) { RqRow(r: r, wide: hSize == .regular) }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) { toDelete = r } label: { Label("Удалить", systemImage: "trash") }
                    }
                    .swipeActions(edge: .leading) {
                        Button { duplicate(r) } label: { Label("Копия", systemImage: "plus.square.on.square") }.tint(.pto)
                        Button { cycle(r) } label: { Label("Статус", systemImage: "arrow.triangle.2.circlepath") }.tint(.orange)
                    }
                    .contextMenu { rowMenu(r) }
                    .listRowBackground(theme.panel())
            }
            if rows.isEmpty {
                EmptyNote(title: query.isEmpty ? "Заявок нет" : "Ничего не найдено",
                          text: query.isEmpty ? "Нажмите «+», чтобы создать заявку." : "Попробуйте другое слово: номер, материал или цех.")
            }
        }
        .listStyle(.insetGrouped)
        .ptoScreen()
        .safeAreaInset(edge: .top, spacing: 0) { sectionBar }
        .searchable(text: $query, prompt: "Заявки и материалы")
        .navigationTitle("Заявки на ТМЦ")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(for: RqRoute.self) { route in
            if let r = store.get("requests", route.id) { RequestEditView(rec: r, isNew: false) } else { Text("Заявка удалена") }
        }
        .navigationDestination(isPresented: $showDash) { RequestsDashView() }
        .navigationDestination(isPresented: $showAct) { ActualizeView() }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                HStack(spacing: 14) {
                    moreMenu(rows)
                    Button { newReq = Rq.blank(store, sec: sec == "all" ? nil : sec) } label: { Image(systemName: "plus") }
                        .accessibilityLabel("Новая заявка")
                }
            }
        }
        .sheet(item: $newReq) { r in NavigationStack { RequestEditView(rec: r, isNew: true) } }
        .confirmationDialog("Удалить заявку?", isPresented: Binding(get: { toDelete != nil }, set: { if !$0 { toDelete = nil } }),
                            titleVisibility: .visible, presenting: toDelete) { r in
            Button("Удалить № \(Rq.title(r.v))", role: .destructive) { withAnimation { store.delete("requests", r.id) } }
        }
        .overlay(alignment: .bottom) { bannerView }
        .refreshable { await store.sync() }
    }

    private func moreMenu(_ rows: [Rec]) -> some View {
        Menu {
            Button { showDash = true } label: { Label("Сводка заявок", systemImage: "chart.bar") }
            Button { showAct = true } label: { Label("Актуализировать", systemImage: "checkmark.seal") }
            ShareLink(item: Rq.listText(rows, store: store)) { Label("Список текстом", systemImage: "text.alignleft") }
            ShareLink(item: RqCSVFile(name: "Заявки.csv", text: Rq.listCSV(rows, store: store)),
                      preview: SharePreview("Заявки.csv")) { Label("Список для Excel (CSV)", systemImage: "tablecells") }
        } label: { Image(systemName: "ellipsis.circle") }
            .accessibilityLabel("Ещё")
    }

    @ViewBuilder private func rowMenu(_ r: Rec) -> some View {
        Button { duplicate(r) } label: { Label("Копия как новая", systemImage: "plus.square.on.square") }
        ForEach(reqStatuses, id: \.self) { s in
            Button { setStatus(r, s) } label: { Label(s, systemImage: Rq.status(r.v) == s ? "checkmark" : "circle") }
        }
        Button(role: .destructive) { toDelete = r } label: { Label("Удалить", systemImage: "trash") }
    }

    @ViewBuilder private var bannerView: some View {
        if let b = banner {
            Text(b).font(.subheadline.weight(.medium)).padding(.horizontal, 16).padding(.vertical, 10)
                .background(.ultraThinMaterial, in: Capsule()).padding(.bottom, 16)
                .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    private var sectionBar: some View {
        let all = store.list("requests")
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Chip(title: "Все", count: all.count, on: sec == "all") { sec = "all" }
                ForEach(store.reqSections) { s in
                    Chip(title: s.name, count: all.filter { $0["sec"].str == s.id }.count, on: sec == s.id) { sec = s.id }
                }
            }
            .padding(.horizontal).padding(.vertical, 8)
        }
        .background(.bar)
    }

    private func duplicate(_ r: Rec) {
        let n = Rq.copy(store, r)
        store.put("requests", n)
        show("Создана копия — заявка № \(n["no"].str)")
    }
    private func setStatus(_ r: Rec, _ s: String) {
        var n = r
        n.v["st"] = .s(s)
        store.put("requests", n)
    }
    private func cycle(_ r: Rec) {
        let i = reqStatuses.firstIndex(of: Rq.status(r.v)) ?? 0
        setStatus(r, reqStatuses[(i + 1) % reqStatuses.count])
    }
    private func show(_ text: String) {
        withAnimation { banner = text }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) { withAnimation { banner = nil } }
    }
}

// MARK: - Строка списка

struct RqRow: View {
    @EnvironmentObject var store: Store
    let r: Rec
    var wide: Bool = false

    var body: some View {
        if wide {
            ViewThatFits(in: .horizontal) {
                wideRow.frame(minWidth: 660)
                compactRow
            }
        } else { compactRow }
    }

    @ViewBuilder private var sectionTag: some View {
        if !r["sec"].str.isEmpty {
            Badge(text: store.secName(r["sec"].str), color: .pto)
        } else if !r["shop"].str.isEmpty {
            Text(r["shop"].str).font(.caption).foregroundStyle(.secondary)
        }
    }
    private var note: String {
        let m15 = r["m15"].str.isEmpty ? "" : "М-15: " + r["m15"].str
        return [r["fnote"].str, m15].filter { !$0.isEmpty }.joined(separator: " · ")
    }
    private var count: some View { Text("\(r["items"].arr.count) поз.").monospacedDigit() }

    private var compactRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text("№ " + Rq.title(r.v)).font(.headline)
                Text(Fmt.show(r["date"].str)).font(.subheadline).foregroundStyle(.secondary)
                Spacer(minLength: 4)
                Badge(text: Rq.statusText(r.v), color: Rq.statusColor(r.v))
            }
            Text(Rq.place(r.v)).font(.subheadline).lineLimit(2)
            if !note.isEmpty { Text(note).font(.caption).foregroundStyle(.secondary).lineLimit(2) }
            HStack(spacing: 8) {
                sectionTag
                count.font(.caption).foregroundStyle(.secondary)
                Spacer(minLength: 4)
                RqGotBar(v: r.v)
            }
        }
        .padding(.vertical, 4)
    }

    private var wideRow: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text("№ " + Rq.title(r.v)).font(.headline)
                Text(Fmt.show(r["date"].str)).font(.caption).foregroundStyle(.secondary)
            }
            .frame(width: 110, alignment: .leading)
            sectionTag.frame(width: 150, alignment: .leading)
            VStack(alignment: .leading, spacing: 3) {
                Text(Rq.place(r.v)).font(.subheadline).lineLimit(2)
                if !note.isEmpty { Text(note).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            count.font(.subheadline).frame(width: 70, alignment: .trailing)
            VStack(alignment: .trailing, spacing: 4) {
                Badge(text: Rq.statusText(r.v), color: Rq.statusColor(r.v))
                RqGotBar(v: r.v)
            }
            .frame(width: 150, alignment: .trailing)
        }
        .padding(.vertical, 6)
    }
}

/// Полоса «получено N из M позиций»
struct RqGotBar: View {
    let v: JSON
    var body: some View {
        let g = Rq.got(v)
        if g.tracked && g.total > 0 {
            HStack(spacing: 6) {
                ProgressView(value: Double(g.full), total: Double(g.total))
                    .frame(width: 56).tint(g.full == g.total ? .green : .pto)
                Text("\(g.full) из \(g.total)").font(.caption).monospacedDigit().foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Получено позиций: \(g.full) из \(g.total)")
        }
    }
}
