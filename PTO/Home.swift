import SwiftUI
import Charts

// MARK: - Данные главной (считаются один раз за отрисовку)

struct ShTodayItem: Identifiable {
    let id: String
    let title: String
    let tag: String
    let late: Bool
    let section: ShSection
}

struct ShDayPoint: Identifiable {
    let id: Date
    let meters: Double
}

struct ShHomeData {
    let points: [ShDayPoint]
    let total: Double
    let bySystem: [(name: String, meters: Double)]
    let today: [ShTodayItem]
    let monthRequests: Int
    let openIssues: Int
    let overdueIssues: Int
    let todayTasks: Int
    let monthSpend: Double

    init(store: Store, period: Int) {
        let cal = Calendar.current
        let start = cal.startOfDay(for: Date())
        let dates: [Date] = (0..<period).reversed().compactMap { cal.date(byAdding: .day, value: -$0, to: start) }
        let journal = store.list("journal")
        var perDay: [String: Double] = [:]
        for j in journal { perDay[String(j["date"].str.prefix(10)), default: 0] += j["m"].num ?? 0 }
        points = dates.map { ShDayPoint(id: $0, meters: perDay[Fmt.iso.string(from: $0)] ?? 0) }
        total = points.reduce(0) { $0 + $1.meters }

        let firstKey = dates.first.map { Fmt.iso.string(from: $0) } ?? Fmt.today
        var sys: [String: Double] = [:]
        for j in journal where j["date"].str >= firstKey {
            let name = j["system"].str.isEmpty ? "Без системы" : j["system"].str
            sys[name, default: 0] += j["m"].num ?? 0
        }
        bySystem = sys.filter { $0.value > 0 }.sorted { $0.value > $1.value }.prefix(6).map { (name: $0.key, meters: $0.value) }

        let t0 = Fmt.today
        let month = String(t0.prefix(7))
        let closedStates = ["Закрыто", "Устранено"]
        let issues = store.list("issues").filter { !closedStates.contains($0["status"].str) }
        let late = issues.filter { !$0["due"].str.isEmpty && $0["due"].str < t0 }
        let tasks = store.list("tasks")
            .filter { !($0["done"]?.bool ?? false) && !$0["due"].str.isEmpty && $0["due"].str <= t0 }
            .sorted { $0["due"].str < $1["due"].str }
        let waiting = store.list("requests").filter {
            $0["st"].str == "Заказано" && !$0["eta"].str.isEmpty && $0["eta"].str <= t0
        }

        var items: [ShTodayItem] = []
        for r in waiting {
            let no = r["label"].str.isEmpty ? r["no"].str : r["label"].str
            let late = r["eta"].str < t0
            items.append(ShTodayItem(id: "r" + r.id, title: "Заявка №\(no): ждём поставку",
                                     tag: late ? "с " + Fmt.show(r["eta"].str) : "сегодня", late: late, section: .req))
        }
        for i in late {
            items.append(ShTodayItem(id: "i" + i.id, title: i["text"].str,
                                     tag: "просрочено " + Fmt.show(i["due"].str), late: true, section: .issues))
        }
        for t in tasks {
            let isLate = t["due"].str < t0
            items.append(ShTodayItem(id: "t" + t.id, title: t["text"].str,
                                     tag: isLate ? "просрочено" : "сегодня", late: isLate, section: .tasks))
        }
        today = Array(items.prefix(6))
        monthRequests = store.list("requests").filter { $0["date"].str.hasPrefix(month) }.count
        openIssues = issues.count
        overdueIssues = late.count
        todayTasks = tasks.count
        monthSpend = store.list("expenses").filter { $0["date"].str.hasPrefix(month) }.reduce(0) { $0 + ($1["sum"].num ?? 0) }
    }
}

// MARK: - Главная

struct HomeView: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var theme: ThemeStore
    @Environment(\.colorScheme) private var scheme
    @Environment(\.horizontalSizeClass) private var hSize
    let go: (ShSection) -> Void
    @State private var newReq: Rec?
    @State private var newShift = false
    @State private var period = 30

    private var firstName: String {
        let n = store.kv("name").str
        return n.isEmpty ? "коллега" : (n.components(separatedBy: " ").first ?? n)
    }

    private var greeting: String {
        let h = Calendar.current.component(.hour, from: Date())
        if h < 5 { return "Доброй ночи" }
        if h < 12 { return "Доброе утро" }
        if h < 18 { return "Добрый день" }
        return "Добрый вечер"
    }

    private var workClosing: Rec? {
        store.list("closings").filter { $0["status"].str == "work" }.max { ($0["no"].num ?? 0) < ($1["no"].num ?? 0) }
    }

    var body: some View {
        let data = ShHomeData(store: store, period: period)
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                actions
                if hSize == .regular {
                    HStack(alignment: .top, spacing: 16) {
                        chartCard(data).frame(maxWidth: .infinity)
                        todayCard(data).frame(width: 360)
                    }
                } else {
                    chartCard(data)
                    todayCard(data)
                }
                strip(data)
                closingCard
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
            .frame(maxWidth: 1100)
            .frame(maxWidth: .infinity)
        }
        .refreshable { await store.sync() }
        .navigationTitle("Главная")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .navigationBarTrailing) { SyncPill() } }
        .sheet(item: $newReq) { r in NavigationStack { RequestEditView(rec: r, isNew: true) } }
        .sheet(isPresented: $newShift) { NavigationStack { NewShiftView() } }
        .ptoScreen()
    }

    // MARK: Части

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(Fmt.ruLong.string(from: Date())).font(.title.bold()).minimumScaleFactor(0.7).lineLimit(1)
            Text("\(greeting), \(firstName)").font(.subheadline).foregroundStyle(.secondary)
        }
    }

    private var actions: some View {
        HStack(spacing: 10) {
            Button { newReq = RequestsView.blank(store, sec: nil) } label: {
                Label("Новая заявка", systemImage: "plus").frame(minHeight: 28)
            }
            .buttonStyle(.borderedProminent)
            Button { newShift = true } label: {
                Label("Записать смену", systemImage: "square.and.pencil").frame(minHeight: 28)
            }
            .buttonStyle(.bordered)
        }
        .controlSize(.large)
    }

    private func chartCard(_ d: ShHomeData) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Смонтировано за \(period) дн.").font(.subheadline).foregroundStyle(.secondary)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(Fmt.num(d.total, 0)).font(.system(size: 34, weight: .bold)).monospacedDigit()
                    Text("м").font(.title3).foregroundStyle(.secondary)
                }
                Picker("Период", selection: $period.animation(.easeInOut(duration: 0.25))) {
                    Text("7 дней").tag(7)
                    Text("30 дней").tag(30)
                    Text("90 дней").tag(90)
                }
                .pickerStyle(.segmented)
            }
            metersChart(d)
            Text("по системам").font(.footnote).foregroundStyle(.secondary).padding(.top, 4)
            if d.bySystem.isEmpty {
                Text("За этот период в журнале записей нет").font(.subheadline).foregroundStyle(.secondary)
            } else {
                systemBars(d)
            }
        }
        .padding(14)
        .shPanel(16)
    }

    private func metersChart(_ d: ShHomeData) -> some View {
        let tint = theme.tint(scheme)
        let step = period == 7 ? 1 : (period == 30 ? 5 : 15)
        let weekly = period == 7
        return Chart(d.points) { p in
            BarMark(x: .value("День", p.id, unit: .day), y: .value("Метры", p.meters))
                .foregroundStyle(tint.opacity(p.meters > 0 ? 1 : 0.25))
                .cornerRadius(3)
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .day, count: step)) { _ in
                AxisValueLabel(format: weekly ? Date.FormatStyle().weekday(.abbreviated)
                                              : Date.FormatStyle().day().month(.twoDigits))
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [2, 4]))
                AxisValueLabel {
                    if let v = value.as(Double.self) { Text(Fmt.num(v, 0) + " м") }
                }
            }
        }
        .environment(\.locale, Locale(identifier: "ru_RU"))
        .frame(height: 190)
        .accessibilityLabel("График метров по дням, всего \(Fmt.num(d.total, 0)) метров")
    }

    private func systemBars(_ d: ShHomeData) -> some View {
        let top = max(1, d.bySystem.map { $0.meters }.max() ?? 1)
        let tint = theme.tint(scheme)
        return VStack(spacing: 8) {
            ForEach(d.bySystem, id: \.name) { s in
                HStack(spacing: 10) {
                    Text(s.name).font(.subheadline).lineLimit(1).frame(width: 110, alignment: .leading)
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.secondary.opacity(0.15))
                            Capsule().fill(tint).frame(width: max(4, geo.size.width * s.meters / top))
                        }
                    }
                    .frame(height: 8)
                    Text(Fmt.num(s.meters, 0) + " м").font(.subheadline).monospacedDigit()
                        .frame(width: 70, alignment: .trailing)
                }
            }
        }
    }

    private func todayCard(_ d: ShHomeData) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Сегодня").font(.headline)
            if d.today.isEmpty {
                Text("На сегодня всё сделано").font(.subheadline).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity).padding(.vertical, 24)
            } else {
                ForEach(d.today) { item in
                    Button { go(item.section) } label: {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(item.title).font(.subheadline).lineLimit(2).multilineTextAlignment(.leading)
                            Spacer(minLength: 8)
                            Badge(text: item.tag, color: item.late ? .red : .orange)
                        }
                        .frame(minHeight: 36)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    Divider()
                }
            }
            HStack(spacing: 8) {
                quick("Калькулятор", "function", .calc)
                quick("Задача", "checklist", .tasks)
                quick("Таймер", "timer", .timer)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .shPanel(16)
    }

    private func quick(_ title: String, _ icon: String, _ s: ShSection) -> some View {
        Button { go(s) } label: {
            Label(title, systemImage: icon).font(.footnote).lineLimit(1).minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, minHeight: 28)
        }
        .buttonStyle(.bordered)
    }

    private func strip(_ d: ShHomeData) -> some View {
        let issuesLabel = d.overdueIssues > 0 ? "открытых замечаний, просрочено \(d.overdueIssues)" : "открытых замечаний"
        return LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 12) {
            Tile(value: "\(d.monthRequests)", label: "заявок на ТМЦ за месяц", icon: "shippingbox") { go(.req) }
            Tile(value: "\(d.openIssues)", label: issuesLabel, icon: "exclamationmark.triangle",
                 tint: d.overdueIssues > 0 ? .red : .orange) { go(.issues) }
            Tile(value: "\(d.todayTasks)", label: "задач на сегодня", icon: "checklist") { go(.tasks) }
            Tile(value: Fmt.num(d.monthSpend, 0) + " ₽", label: "расходы за месяц", icon: "rublesign.circle") { go(.expenses) }
        }
    }

    @ViewBuilder private var closingCard: some View {
        if let c = workClosing {
            let schemes = store.list("schemes").filter { $0["closing"].str == c.id }
            let signed = schemes.filter { $0["status"].str == "signed" }.count
            Button { go(.schemes) } label: {
                Card(title: "В работе: закрытие №\(c["no"].str)") {
                    ProgressView(value: Double(signed), total: Double(max(1, schemes.count)))
                    Text("подписано \(signed) из \(schemes.count) схем").font(.footnote).foregroundStyle(.secondary)
                }
            }
            .buttonStyle(Pressable()).foregroundStyle(.primary)
        }
    }
}
