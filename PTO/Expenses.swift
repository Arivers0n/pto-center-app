import SwiftUI

// MARK: - Расходы

struct ExpensesView: View {
    @EnvironmentObject var store: Store
    @State private var query = ""
    @State private var sheet: LsSheet?

    private static let categories = ["Продукты", "Транспорт", "Здоровье", "Развлечения", "Дом", "Одежда", "Прочее"]
    private static let specs: [LsFieldSpec] = [
        LsFieldSpec(key: "date", title: "Дата", kind: .date),
        LsFieldSpec(key: "cat", title: "Категория", kind: .pick(categories)),
        LsFieldSpec(key: "sum", title: "Сумма, ₽", kind: .number),
        LsFieldSpec(key: "note", title: "Заметка")
    ]

    private var all: [Rec] { store.list("expenses") }

    private var rows: [Rec] {
        let q = query.lowercased()
        let found = all.filter { e in
            q.isEmpty || [e["cat"].str, e["note"].str].joined(separator: " ").lowercased().contains(q)
        }
        return found.sorted { a, b in
            if a["date"].str != b["date"].str { return a["date"].str > b["date"].str }
            return a.id > b.id
        }
    }

    private var monthItems: [Rec] {
        let ym = String(Fmt.today.prefix(7))
        return all.filter { $0["date"].str.hasPrefix(ym) }
    }

    private var byCategory: [(cat: String, sum: Double)] {
        var sums: [String: Double] = [:]
        for e in monthItems { sums[e["cat"].str, default: 0] += e["sum"].num ?? 0 }
        return sums.map { (cat: $0.key, sum: $0.value) }.sorted { $0.sum > $1.sum }
    }

    private var monthTotal: Double {
        var total: Double = 0
        for e in monthItems { total += e["sum"].num ?? 0 }
        return total
    }

    private func money(_ v: Double) -> String { Fmt.num(v, 0) + " ₽" }

    var body: some View {
        List {
            Section("За месяц: " + money(monthTotal)) {
                if byCategory.isEmpty {
                    Text("Расходов в этом месяце пока нет. Запишите первый кнопкой «+».")
                        .font(.subheadline).foregroundStyle(.secondary)
                } else {
                    bars
                }
            }
            Section("Все записи") {
                if rows.isEmpty && !all.isEmpty {
                    EmptyNote(title: "Ничего не найдено", text: "Измените поиск.")
                }
                ForEach(rows) { e in row(e) }
            }
        }
        .navigationTitle("Расходы")
        .searchable(text: $query, prompt: "Категория или заметка")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button { sheet = LsSheet(rec: nil) } label: { Image(systemName: "plus") }
                    .accessibilityLabel("Добавить расход")
            }
        }
        .sheet(item: $sheet) { s in form(s) }
        .lsColumn()
        .ptoScreen()
    }

    private var bars: some View {
        let maxSum = max(1, byCategory.map { $0.sum }.max() ?? 1)
        return VStack(spacing: 10) {
            ForEach(byCategory, id: \.cat) { item in
                HStack(spacing: 10) {
                    Text(item.cat).font(.subheadline).frame(width: 96, alignment: .leading).lineLimit(1)
                    GeometryReader { geo in
                        Capsule().fill(Color.pto)
                            .frame(width: max(6, geo.size.width * item.sum / maxSum), height: 10)
                            .frame(maxHeight: .infinity, alignment: .center)
                    }
                    .frame(height: 16)
                    Text(money(item.sum)).font(.subheadline).monospacedDigit()
                        .frame(minWidth: 72, alignment: .trailing)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .padding(.vertical, 4)
    }

    private func row(_ e: Rec) -> some View {
        Button { sheet = LsSheet(rec: e) } label: {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(e["cat"].str).foregroundStyle(.primary)
                    Text([Fmt.show(e["date"].str), e["note"].str].filter { !$0.isEmpty }.joined(separator: " · "))
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Text(money(e["sum"].num ?? 0)).monospacedDigit().foregroundStyle(.primary)
            }
            .frame(minHeight: 44)
        }
        .lsSwipeDelete { withAnimation { store.delete("expenses", e.id) } }
    }

    private func form(_ s: LsSheet) -> some View {
        LsRecordForm(title: s.rec == nil ? "Новый расход" : "Расход", specs: Self.specs, rec: s.rec,
                     defaults: ["date": Fmt.today, "cat": "Продукты"],
                     required: (key: "sum", message: "Укажите сумму в рублях"),
                     onSave: { r in withAnimation { store.put("expenses", r) } },
                     onDelete: { r in store.delete("expenses", r.id) })
    }
}
