import SwiftUI

// MARK: - История материала в заявках (как matHistory / matFind в вебе)

private struct LsMatHistory {
    let count: Int
    let totals: [(unit: String, qty: Double)]
    let lastRequest: Rec
    let lastItem: JSON
}

private struct LsMatFound: Identifiable {
    let id: String
    let name: String
    let count: Int
    let qty: Double
    let unit: String
}

private func lsMatKey(_ s: String) -> String {
    var t = s.lowercased().replacingOccurrences(of: "ё", with: "е")
    for ch in [" ", "\"", "'", "«", "»", ",", ".", ";", ":", "(", ")", "\\", "-"] { t = t.replacingOccurrences(of: ch, with: "") }
    for ch in ["х", "×"] { t = t.replacingOccurrences(of: ch, with: "x") }
    for ch in ["ф", "⌀", "ø"] { t = t.replacingOccurrences(of: ch, with: "ф") }
    return t
}

private func lsMatHistory(_ name: String, _ requests: [Rec]) -> LsMatHistory? {
    let key = lsMatKey(name)
    guard key.count >= 3 else { return nil }
    var count = 0
    var order: [String] = []
    var byUnit: [String: Double] = [:]
    var last: (Rec, JSON)?
    for r in requests {
        for item in r["items"].arr where lsMatKey(item["name"].str) == key {
            count += 1
            let unit = item["unit"].str.isEmpty ? "—" : item["unit"].str
            if byUnit[unit] == nil { order.append(unit) }
            byUnit[unit, default: 0] += item["qty"].num ?? 0
            if last == nil || r["date"].str > last!.0["date"].str { last = (r, item) }
        }
    }
    guard count > 0, let last else { return nil }
    return LsMatHistory(count: count, totals: order.map { ($0, byUnit[$0] ?? 0) }, lastRequest: last.0, lastItem: last.1)
}

private func lsMatFind(_ q: String, _ requests: [Rec]) -> [LsMatFound] {
    let needle = q.lowercased()
    var map: [String: LsMatFound] = [:]
    for r in requests {
        for item in r["items"].arr {
            let name = item["name"].str.trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty, name.lowercased().contains(needle) else { continue }
            let key = lsMatKey(name)
            let old = map[key]
            map[key] = LsMatFound(id: key, name: old?.name ?? name, count: (old?.count ?? 0) + 1,
                                  qty: (old?.qty ?? 0) + (item["qty"].num ?? 0), unit: old?.unit ?? item["unit"].str)
        }
    }
    return Array(map.values.sorted { $0.count > $1.count }.prefix(5))
}

private func lsHistoryText(_ h: LsMatHistory) -> String {
    let sums = h.totals.map { Fmt.num($0.qty) + " " + $0.unit }.joined(separator: " + ")
    let r = h.lastRequest, item = h.lastItem
    let no = r["label"].str.isEmpty ? r["no"].str : r["label"].str
    let got = item["got"]
    var tail = ", получение не отмечено"
    if let g = got, !g.str.isEmpty { tail = ", получено " + Fmt.num(g.num ?? 0) }
    else if r["st"].str == "Поставлено" { tail = ", поставлено" }
    return "Заказывали \(lsPlural(h.count, "раз", "раза", "раз")), всего \(sums). Последняя — №\(no) от \(Fmt.show(r["date"].str)): "
        + "\(Fmt.num(item["qty"].num ?? 0)) \(item["unit"].str)\(tail)."
}

// MARK: - Материалы на объекте

struct MaterialsView: View {
    @EnvironmentObject var store: Store
    @State private var query = ""
    @State private var sheet: LsSheet?

    private static let specs: [LsFieldSpec] = [
        LsFieldSpec(key: "name", title: "Наименование", kind: .multiline),
        LsFieldSpec(key: "unit", title: "Ед."),
        LsFieldSpec(key: "rec", title: "Получено", kind: .number),
        LsFieldSpec(key: "used", title: "Использовано", kind: .number),
        LsFieldSpec(key: "doc", title: "Документ")
    ]

    private func rest(_ m: Rec) -> Double { (m["rec"].num ?? 0) - (m["used"].num ?? 0) }

    private var rows: [Rec] {
        let q = query.lowercased()
        let all = store.list("mats")
        let found = q.isEmpty ? all : all.filter { ([$0["name"].str, $0["doc"].str].joined(separator: " ")).lowercased().contains(q) }
        return found.sorted { $0["name"].str.localizedCaseInsensitiveCompare($1["name"].str) == .orderedAscending }
    }

    private var inRequests: [LsMatFound] {
        query.trimmingCharacters(in: .whitespaces).count < 2 ? [] : lsMatFind(query, store.list("requests"))
    }

    private var csv: LsCSV {
        let head = ["Материал", "Ед.", "Получено", "Использовано", "Остаток", "Документ"]
        let body: [[String]] = store.list("mats").map { m in
            [m["name"].str, m["unit"].str, lsPlain(m["rec"].num ?? 0), lsPlain(m["used"].num ?? 0), lsPlain(rest(m)), m["doc"].str]
        }
        return LsCSV(name: "Материалы.csv", rows: [head] + body)
    }

    var body: some View {
        List {
            Section {
                if rows.isEmpty {
                    EmptyNote(title: store.list("mats").isEmpty ? "Материалов пока нет" : "Ничего не найдено",
                              text: store.list("mats").isEmpty ? "Добавьте первый материал кнопкой «+»." : "Измените поиск.")
                }
                ForEach(rows) { m in row(m) }
            } footer: {
                Text("Получено, использовано, остаток — красным перерасход")
            }
            if !inRequests.isEmpty {
                Section("В заявках") {
                    ForEach(inRequests) { f in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(f.name)
                            Text("\(lsPlural(f.count, "раз", "раза", "раз")), всего \(Fmt.num(f.qty)) \(f.unit)")
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                        .frame(minHeight: 44, alignment: .leading)
                    }
                }
            }
        }
        .navigationTitle("Материалы на объекте")
        .searchable(text: $query, prompt: "Поиск материала")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                HStack {
                    if !store.list("mats").isEmpty { LsShareButton(csv: csv) }
                    Button { sheet = LsSheet(rec: nil) } label: { Image(systemName: "plus") }
                        .accessibilityLabel("Добавить материал")
                }
            }
        }
        .sheet(item: $sheet) { s in form(s) }
        .lsColumn()
        .ptoScreen()
    }

    private func row(_ m: Rec) -> some View {
        let left = rest(m)
        let tint: Color = left < 0 ? .red : (left == 0 ? .green : .secondary)
        let unit = m["unit"].str
        return Button { sheet = LsSheet(rec: m) } label: {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(m["name"].str).foregroundStyle(.primary).multilineTextAlignment(.leading)
                    Text("Получено \(Fmt.num(m["rec"].num ?? 0, 3)) · использовано \(Fmt.num(m["used"].num ?? 0, 3)) \(unit)")
                        .font(.footnote).foregroundStyle(.secondary).monospacedDigit()
                    if !m["doc"].str.isEmpty { Text(m["doc"].str).font(.footnote).foregroundStyle(.secondary) }
                }
                Spacer(minLength: 8)
                Badge(text: "ост. " + Fmt.num(left, 3), color: tint)
            }
            .frame(minHeight: 44, alignment: .leading)
        }
        .lsSwipeDelete { withAnimation { store.delete("mats", m.id) } }
    }

    private func form(_ s: LsSheet) -> some View {
        let requests = store.list("requests")
        let hint: ([String: String]) -> String? = { draft in
            guard let h = lsMatHistory(draft["name"] ?? "", requests) else { return nil }
            return lsHistoryText(h)
        }
        return LsRecordForm(title: s.rec == nil ? "Новый материал" : "Материал", specs: Self.specs, rec: s.rec,
                            defaults: ["unit": "шт"],
                            required: (key: "name", message: "Укажите название материала"),
                            hint: hint,
                            newExtras: ["used": .n(0)],
                            onSave: { r in withAnimation { store.put("mats", r) } },
                            onDelete: { r in store.delete("mats", r.id) })
    }
}
