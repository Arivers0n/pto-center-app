import SwiftUI

// MARK: - Реестр сварных стыков

struct JointsView: View {
    @EnvironmentObject var store: Store
    @State private var query = ""
    @State private var filter = "Все"
    @State private var sheet: LsSheet?

    private static let results = ["Годен", "Ожидается", "Брак"]
    private static let specs: [LsFieldSpec] = [
        LsFieldSpec(key: "no", title: "№ стыка"),
        LsFieldSpec(key: "size", title: "Размер трубы"),
        LsFieldSpec(key: "line", title: "Линия / система"),
        LsFieldSpec(key: "welder", title: "Сварщик (клеймо)"),
        LsFieldSpec(key: "date", title: "Дата", kind: .date),
        LsFieldSpec(key: "ctrl", title: "Контроль", kind: .pick(["ВИК", "УЗК", "РК", "Не требуется"])),
        LsFieldSpec(key: "result", title: "Результат", kind: .pick(results)),
        LsFieldSpec(key: "note", title: "Примечание", kind: .multiline)
    ]

    private func color(_ result: String) -> Color {
        result == "Годен" ? .green : (result == "Брак" ? .red : .orange)
    }

    private var all: [Rec] { store.list("joints") }

    private var rows: [Rec] {
        let q = query.lowercased()
        let found = all.filter { r in
            let byResult = filter == "Все" || r["result"].str == filter
            let hay = [r["no"].str, r["size"].str, r["line"].str, r["welder"].str, r["note"].str].joined(separator: " ").lowercased()
            return byResult && (q.isEmpty || hay.contains(q))
        }
        return found.sorted { a, b in
            if a["date"].str != b["date"].str { return a["date"].str > b["date"].str }
            return a["no"].str > b["no"].str
        }
    }

    private var chips: [(title: String, count: Int?)] {
        var out: [(title: String, count: Int?)] = [("Все", all.count)]
        for s in Self.results { out.append((s, all.filter { $0["result"].str == s }.count)) }
        return out
    }

    private var csv: LsCSV {
        let head = ["№ стыка", "Размер", "Линия", "Сварщик", "Дата", "Контроль", "Результат", "Примечание"]
        let body: [[String]] = rows.map { j in
            [j["no"].str, j["size"].str, j["line"].str, j["welder"].str, Fmt.show(j["date"].str),
             j["ctrl"].str, j["result"].str, j["note"].str]
        }
        return LsCSV(name: "Стыки.csv", rows: [head] + body)
    }

    var body: some View {
        List {
            if !all.isEmpty {
                LsChips(items: chips, selected: $filter)
                Section { stats }
            }
            Section {
                if rows.isEmpty {
                    EmptyNote(title: all.isEmpty ? "Стыков пока нет" : "Ничего не найдено",
                              text: all.isEmpty ? "Добавьте первый стык кнопкой «+»." : "Измените поиск или фильтр.")
                }
                ForEach(rows) { r in row(r) }
            } footer: {
                Text("Клеймо сварщика, вид контроля и заключение")
            }
        }
        .navigationTitle("Реестр сварных стыков")
        .searchable(text: $query, prompt: "Номер, линия, сварщик")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                HStack {
                    if !all.isEmpty { LsShareButton(csv: csv) }
                    Button { sheet = LsSheet(rec: nil) } label: { Image(systemName: "plus") }
                        .accessibilityLabel("Добавить стык")
                }
            }
        }
        .sheet(item: $sheet) { s in form(s) }
        .lsColumn()
        .ptoScreen()
    }

    private var stats: some View {
        let total = all.count
        let ok = all.filter { $0["result"].str == "Годен" }.count
        let bad = all.filter { $0["result"].str == "Брак" }.count
        let badShare = total == 0 ? "0" : Fmt.num(Double(bad) / Double(total) * 100, 1)
        return HStack {
            LsStat(value: "\(total)", label: "всего стыков")
            LsStat(value: "\(ok)", label: "годен", tint: .green)
            LsStat(value: "\(bad)", label: "брак \(badShare)%", tint: .red)
            LsStat(value: "\(total - ok - bad)", label: "ожидают заключения", tint: .orange)
        }
    }

    private func row(_ r: Rec) -> some View {
        Button { sheet = LsSheet(rec: r) } label: {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(r["no"].str).font(.headline).foregroundStyle(.primary)
                    Text([r["size"].str, r["line"].str].filter { !$0.isEmpty }.joined(separator: " · "))
                        .font(.footnote).foregroundStyle(.secondary)
                    Text([r["welder"].str, r["ctrl"].str, Fmt.show(r["date"].str)].filter { !$0.isEmpty }.joined(separator: " · "))
                        .font(.footnote).foregroundStyle(.secondary)
                    if !r["note"].str.isEmpty {
                        Text(r["note"].str).font(.footnote).foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 8)
                Badge(text: r["result"].str, color: color(r["result"].str))
            }
            .frame(minHeight: 44, alignment: .leading)
        }
        .lsSwipeDelete { withAnimation { store.delete("joints", r.id) } }
    }

    private func form(_ s: LsSheet) -> some View {
        LsRecordForm(title: s.rec == nil ? "Новый стык" : "Стык", specs: Self.specs, rec: s.rec,
                     defaults: ["size": "Труба 76х3,5", "line": "В1.1", "date": Fmt.today, "ctrl": "ВИК", "result": "Ожидается"],
                     required: (key: "no", message: "Укажите номер стыка"),
                     onSave: { r in withAnimation { store.put("joints", r) } },
                     onDelete: { r in store.delete("joints", r.id) })
    }
}
