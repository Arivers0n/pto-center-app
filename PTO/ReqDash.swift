import SwiftUI
import Charts

private let rqMonthShort = ["янв", "фев", "мар", "апр", "май", "июн", "июл", "авг", "сен", "окт", "ноя", "дек"]
private let rqMonthFull = ["январь", "февраль", "март", "апрель", "май", "июнь", "июль", "август", "сентябрь", "октябрь", "ноябрь", "декабрь"]
private let rqTopLimit = 12
private let rqMonthsShown = 12
private let rqDashWidth: CGFloat = 1000

private struct RqMonth: Identifiable {
    let id: String
    let label: String
    let full: String
    let n: Int
    let positions: Int
}

private struct RqMaterial: Identifiable {
    let id: String
    let title: String
    var count = 0
    var requests = Set<String>()
    var units: [String: Double] = [:]

    var totals: String {
        let top = units.sorted { $0.value > $1.value }.prefix(2)
        return top.map { Fmt.num($0.value, 2) + " " + $0.key }.joined(separator: " + ")
    }
}

private struct RqSecStat: Identifiable {
    let id: String
    let name: String
    let full: String
    let n: Int
    let positions: Int
    let last: String
}

/// Сводка заявок: что заказано, по каким разделам и что ещё не пришло (PAGES.reqdash)
struct RequestsDashView: View {
    @EnvironmentObject var store: Store

    private var reqs: [Rec] { store.list("requests") }

    var body: some View {
        let list = reqs
        ScrollView {
            VStack(spacing: 16) {
                if list.isEmpty {
                    EmptyNote(title: "Заявок пока нет", text: "Создайте заявку в разделе «Заявки на ТМЦ».")
                } else {
                    tiles(list)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 340), spacing: 16, alignment: .top)], spacing: 16) {
                        monthsCard(list)
                        sectionsCard(list)
                        materialsCard(list)
                        waitCard(list)
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: rqDashWidth)
            .frame(maxWidth: .infinity)
        }
        .ptoScreen()
        .navigationTitle("Сводка заявок")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: Показатели

    private func tiles(_ list: [Rec]) -> some View {
        let positions = list.flatMap { r in r["items"].arr.map { (r, $0) } }
        let got = positions.filter { (pair: (Rec, JSON)) -> Bool in
            let q = pair.1["qty"].num ?? 0
            return pair.0["st"].str == "Поставлено" || ((pair.1["got"].num ?? 0) >= q && q > 0)
        }.count
        let wait = list.filter { $0["st"].str == "Заказано" }
        let late = wait.filter { Rq.isLate($0.v) }.count
        let percent = positions.isEmpty ? 0 : Int((Double(got) / Double(positions.count) * 100).rounded())
        let waitLabel = late > 0 ? "ждём поставку, просрочено \(late)" : "ждём поставку"
        return LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 12) {
            Tile(value: Fmt.num(Double(list.count), 0), label: "заявок", icon: "shippingbox", tap: {})
            Tile(value: Fmt.num(Double(positions.count), 0), label: "позиций в заявках", icon: "list.bullet", tap: {})
            Tile(value: "\(percent)%", label: "позиций отмечено полученными", icon: "checkmark.circle", tint: .green, tap: {})
            Tile(value: "\(wait.count)", label: waitLabel, icon: "clock", tint: late > 0 ? .red : .orange, tap: {})
        }
    }

    // MARK: По месяцам

    private func months(_ list: [Rec]) -> [RqMonth] {
        var acc: [String: (n: Int, p: Int)] = [:]
        for r in list {
            let d = r["date"].str
            guard d.count >= 7 else { continue }
            let k = String(d.prefix(7))
            let cur = acc[k] ?? (0, 0)
            acc[k] = (cur.n + 1, cur.p + r["items"].arr.count)
        }
        return acc.keys.sorted().suffix(rqMonthsShown).compactMap { k -> RqMonth? in
            guard let m = Int(k.suffix(2)), (1...12).contains(m), let a = acc[k] else { return nil }
            return RqMonth(id: k, label: rqMonthShort[m - 1], full: rqMonthFull[m - 1] + " " + String(k.prefix(4)), n: a.n, positions: a.p)
        }
    }

    private func monthsCard(_ list: [Rec]) -> some View {
        let data = months(list)
        return Card(title: "Заявки по месяцам") {
            if data.isEmpty {
                Text("У заявок нет дат.").font(.footnote).foregroundStyle(.secondary)
            } else {
                Chart(data) { m in
                    BarMark(x: .value("Месяц", m.label), y: .value("Заявок", m.n))
                        .cornerRadius(4)
                        .foregroundStyle(Color.pto)
                        .annotation(position: .top) { Text("\(m.n)").font(.caption2).monospacedDigit().foregroundStyle(.secondary) }
                        .accessibilityLabel(m.full)
                        .accessibilityValue("\(m.n) заявок, \(m.positions) позиций")
                }
                .chartYAxis(.hidden)
                .frame(height: 200)
            }
        }
    }

    // MARK: По разделам

    private func sectionStats(_ list: [Rec]) -> [RqSecStat] {
        store.reqSections.map { s -> RqSecStat in
            let rs = list.filter { $0["sec"].str == s.id }
            let last = rs.map { $0["date"].str }.sorted().last ?? ""
            return RqSecStat(id: s.id, name: s.name, full: s.full, n: rs.count, positions: rs.reduce(0) { $0 + $1["items"].arr.count }, last: last)
        }
    }

    private func sectionsCard(_ list: [Rec]) -> some View {
        let stats = sectionStats(list)
        let top = max(1, stats.map(\.n).max() ?? 1)
        let noSec = list.filter { $0["sec"].str.isEmpty }.count
        return Card(title: "По разделам") {
            ForEach(stats) { x in
                NavigationLink { RequestsView(initialSec: x.id) } label: {
                    HStack(spacing: 10) {
                        Text(x.name).font(.subheadline).frame(width: 120, alignment: .leading).lineLimit(1)
                        GeometryReader { geo in
                            Capsule().fill(Color.pto.opacity(0.85))
                                .frame(width: max(x.n > 0 ? 4 : 0, geo.size.width * CGFloat(x.n) / CGFloat(top)))
                        }
                        .frame(height: 8)
                        Text("\(x.n)").font(.subheadline).monospacedDigit().frame(minWidth: 28, alignment: .trailing)
                    }
                    .frame(minHeight: 36)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(x.full): \(x.n) заявок, \(x.positions) позиций" + (x.last.isEmpty ? "" : ", последняя " + Fmt.show(x.last)))
            }
            if noSec > 0 { Text("Без раздела: \(noSec)").font(.footnote).foregroundStyle(.secondary) }
        }
    }

    // MARK: Чаще всего заказывают

    private func materials(_ list: [Rec]) -> [RqMaterial] {
        var map: [String: RqMaterial] = [:]
        for r in list {
            for i in r["items"].arr {
                let name = i["name"].str.trimmingCharacters(in: .whitespaces)
                let key = Rq.mkey(name)
                guard !key.isEmpty else { continue }
                var m = map[key] ?? RqMaterial(id: key, title: name)
                m.count += 1
                m.requests.insert(r.id)
                let unit = i["unit"].str.isEmpty ? "—" : i["unit"].str
                m.units[unit, default: 0] += i["qty"].num ?? 0
                map[key] = m
            }
        }
        let sorted = map.values.sorted { (a: RqMaterial, b: RqMaterial) -> Bool in
            if a.requests.count != b.requests.count { return a.requests.count > b.requests.count }
            if a.count != b.count { return a.count > b.count }
            return a.title < b.title
        }
        return Array(sorted.prefix(rqTopLimit))
    }

    private func materialsCard(_ list: [Rec]) -> some View {
        Card(title: "Чаще всего заказывают") {
            ForEach(materials(list)) { m in
                NavigationLink { RequestsView(initialQuery: m.title) } label: {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(m.title).font(.subheadline).lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
                        Text("\(m.requests.count) заяв.").font(.caption).foregroundStyle(.secondary).monospacedDigit()
                        Text(m.totals).font(.caption.weight(.medium)).monospacedDigit().multilineTextAlignment(.trailing)
                    }
                    .frame(minHeight: 36)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Divider()
            }
        }
    }

    // MARK: Ждём поставку

    private func waitCard(_ list: [Rec]) -> some View {
        let wait = list.filter { $0["st"].str == "Заказано" }.sorted { (a: Rec, b: Rec) -> Bool in
            let ea = Rq.eta(a.v).isEmpty ? "9" : Rq.eta(a.v)
            let eb = Rq.eta(b.v).isEmpty ? "9" : Rq.eta(b.v)
            return ea == eb ? a.id < b.id : ea < eb
        }
        return Card(title: "Ждём поставку") {
            if wait.isEmpty {
                Text("Нет заявок со статусом «Заказано». В списке заявок смахните строку вправо и нажмите «Статус», чтобы отметить заказ, а в заявке укажите дату поставки.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            ForEach(wait.prefix(rqTopLimit)) { r in
                NavigationLink { RequestEditView(rec: r, isNew: false) } label: {
                    HStack(spacing: 10) {
                        Text("№ " + Rq.title(r.v)).font(.subheadline.weight(.semibold))
                        Text(store.secName(r["sec"].str)).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        Spacer(minLength: 4)
                        Badge(text: Rq.eta(r.v).isEmpty ? "дата не указана" : Fmt.show(Rq.eta(r.v)),
                              color: Rq.eta(r.v).isEmpty ? .secondary : (Rq.isLate(r.v) ? .red : .orange))
                        Text("\(r["items"].arr.count)").font(.caption).monospacedDigit().foregroundStyle(.secondary)
                    }
                    .frame(minHeight: 36)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Divider()
            }
        }
    }
}
