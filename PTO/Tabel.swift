import SwiftUI

// MARK: - Табель: данные в kv «tab» (месяц → день → запись) и kv «tabCfg» (правила), как в вебе

private let lsDayTypes = ["Раб", "Вых", "Отп", "Бол", "Ком"]
private let lsDayTypeNames = ["Раб": "Работа", "Вых": "Выходной", "Отп": "Отпуск", "Бол": "Больничный", "Ком": "Командировка"]
private let lsWeekdays = ["вс", "пн", "вт", "ср", "чт", "пт", "сб"]
private let lsMonths = ["Январь", "Февраль", "Март", "Апрель", "Май", "Июнь", "Июль", "Август", "Сентябрь", "Октябрь", "Ноябрь", "Декабрь"]
private let lsCalendar = Calendar(identifier: .gregorian)

private struct LsTabCfg {
    var norm: Double = 8
    var start = "08:00"
    var end = "17:00"
    var lunch: Double = 60

    init(_ j: JSON?) {
        if let n = j?["norm"].num, n > 0 { norm = n }
        if let s = j?["start"], !s.str.isEmpty { start = s.str }
        if let e = j?["end"], !e.str.isEmpty { end = e.str }
        if let l = j?["lunch"].num { lunch = l }
    }

    var json: JSON { .o(["norm": .n(norm), "start": .s(start), "end": .s(end), "lunch": .n(lunch)]) }
}

private struct LsDay: Equatable {
    var type = ""
    var inT = ""
    var outT = ""
    var lunch: Double
    var note = ""

    init(lunch: Double) { self.lunch = lunch }

    init(_ j: JSON?, cfg: LsTabCfg) {
        type = j?["type"].str ?? ""
        inT = j?["in"].str ?? ""
        outT = j?["out"].str ?? ""
        lunch = j?["lunch"].num ?? cfg.lunch
        note = j?["note"].str ?? ""
    }

    var json: JSON {
        .o(["type": .s(type), "in": .s(inT), "out": .s(outT), "lunch": .n(lunch), "note": .s(note)])
    }

    var isEmpty: Bool { type.isEmpty && inT.isEmpty && outT.isEmpty }

    var hours: Double {
        guard ["Раб", "Ком", "Вых"].contains(type), let a = lsMinutes(inT), let b = lsMinutes(outT) else { return 0 }
        var m = b - a
        if m < 0 { m += 1440 }
        return max(0, (Double(m) - lunch) / 60)
    }
}

private func lsMinutes(_ s: String) -> Int? {
    let p = s.split(separator: ":")
    guard p.count == 2, let h = Int(p[0]), let m = Int(p[1]), h < 24, m < 60 else { return nil }
    return h * 60 + m
}

private func lsHM(_ h: Double) -> String {
    let m = Int((h * 60).rounded())
    return "\(m / 60):" + String(format: "%02d", m % 60)
}

private func lsNowHM() -> String {
    let c = lsCalendar.dateComponents([.hour, .minute], from: Date())
    return String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
}

private func lsMonthDays(_ ym: String) -> [String] {
    guard let first = Fmt.date(ym + "-01"), let range = lsCalendar.range(of: .day, in: .month, for: first) else { return [] }
    return range.map { ym + "-" + String(format: "%02d", $0) }
}

private func lsWeekday(_ key: String) -> Int {
    guard let d = Fmt.date(key) else { return 1 }
    return lsCalendar.component(.weekday, from: d)
}

private func lsIsWeekend(_ key: String) -> Bool {
    let w = lsWeekday(key)
    return w == 1 || w == 7
}

private func lsShiftMonth(_ ym: String, _ delta: Int) -> String {
    guard let d = Fmt.date(ym + "-01"), let n = lsCalendar.date(byAdding: .month, value: delta, to: d) else { return ym }
    return String(Fmt.iso.string(from: n).prefix(7))
}

private let lsTimeFormat: DateFormatter = {
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    f.dateFormat = "HH:mm"
    return f
}()

// MARK: - Экран

private struct LsDayRef: Identifiable { let id: String }

private struct LsStats {
    var hours = 0.0, over = 0.0, weekend = 0.0, norm = 0.0
    var days = 0, normalDays = 0
}

struct TabelView: View {
    @EnvironmentObject private var theme: ThemeStore
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject var store: Store
    @State private var ym = String(Fmt.today.prefix(7))
    @State private var dayRef: LsDayRef?
    @State private var rules = false
    @State private var message: String?

    private var cfg: LsTabCfg { LsTabCfg(store.kv("tabCfg")) }
    private var days: [String] { lsMonthDays(ym) }
    private var isCurrent: Bool { ym == String(Fmt.today.prefix(7)) }
    private var monthJSON: JSON? { store.kv("tab")?[ym] }

    private func day(_ key: String) -> LsDay { LsDay(monthJSON?[key], cfg: cfg) }

    private var title: String {
        let parts = ym.split(separator: "-")
        guard parts.count == 2, let m = Int(parts[1]), m >= 1, m <= 12 else { return ym }
        return lsMonths[m - 1] + " " + parts[0]
    }

    private var stats: LsStats {
        let c = cfg
        var s = LsStats()
        for k in days {
            if !lsIsWeekend(k) { s.normalDays += 1 }
            let d = day(k), h = d.hours
            s.hours += h
            if h > 0 { s.days += 1 }
            if d.type == "Раб" { s.over += max(0, h - c.norm) }
            if d.type == "Вых" { s.weekend += h }
        }
        s.norm = Double(s.normalDays) * c.norm
        return s
    }

    var body: some View {
        List {
            Section {
                monthBar.listRowBackground(theme.panel())
                actions.listRowBackground(theme.panel())
            }
            Section { summary.listRowBackground(theme.panel()) }
            Section {
                ForEach(days, id: \.self) { k in row(k) }
            } footer: {
                Text("Норма месяца считается по будням календаря (без праздников). «Заполнить будни» проставляет начало, конец и обед из правил в пустые дни.")
            }
        }
        .navigationTitle("Табель")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                HStack {
                    LsShareButton(csv: csv)
                    Button { rules = true } label: { Image(systemName: "slider.horizontal.3") }
                        .accessibilityLabel("Правила табеля")
                }
            }
        }
        .sheet(item: $dayRef) { ref in
            LsDaySheet(key: ref.id, day: day(ref.id), cfg: cfg) { d in write([ref.id: d]) }
        }
        .sheet(isPresented: $rules) {
            LsRulesSheet(cfg: cfg) { c in store.setKV("tabCfg", c.json) }
        }
        .overlay(alignment: .bottom) {
            if let message {
                Text(message).font(.subheadline.weight(.medium)).padding(.horizontal, 14).padding(.vertical, 8)
                    .background(.ultraThinMaterial, in: Capsule()).padding(.bottom, 16).transition(.opacity)
            }
        }
        .lsColumn()
        .ptoScreen()
    }

    private var monthBar: some View {
        HStack {
            Button { withAnimation { ym = lsShiftMonth(ym, -1) } } label: { Image(systemName: "chevron.left").frame(width: 44, height: 44) }
                .buttonStyle(.borderless).accessibilityLabel("Предыдущий месяц")
            Spacer()
            Text(title).font(.headline)
            Spacer()
            Button { withAnimation { ym = lsShiftMonth(ym, 1) } } label: { Image(systemName: "chevron.right").frame(width: 44, height: 44) }
                .buttonStyle(.borderless).accessibilityLabel("Следующий месяц")
        }
    }

    private var actions: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) { actionButtons }
            VStack(spacing: 8) { actionButtons }
        }
    }

    @ViewBuilder private var actionButtons: some View {
        Button { clockIn() } label: { Text("Пришёл").foregroundStyle(theme.onTint(colorScheme)).frame(maxWidth: .infinity, minHeight: 36) }
            .buttonStyle(.borderedProminent).disabled(!isCurrent)
        Button { clockOut() } label: { Text("Ушёл").frame(maxWidth: .infinity, minHeight: 36) }
            .buttonStyle(.bordered).disabled(!isCurrent)
        Button { fillWeekdays() } label: { Text("Заполнить будни").frame(maxWidth: .infinity, minHeight: 36) }
            .buttonStyle(.bordered)
    }

    private var summary: some View {
        let s = stats
        let diff = s.hours - s.norm
        let diffText = (diff > 0 ? "+" : "") + Fmt.num(diff, 1) + " ч"
        var extra = ""
        if s.over > 0 { extra += ", сверх нормы за день " + Fmt.num(s.over, 1) + " ч" }
        if s.weekend > 0 { extra += ", в выходные " + Fmt.num(s.weekend, 1) + " ч" }
        return VStack(spacing: 12) {
            HStack {
                LsStat(value: lsHM(s.hours), label: "отработано, ч:мин")
                LsStat(value: Fmt.num(s.norm, 0) + " ч", label: "норма (\(s.normalDays) буд. дн.)")
            }
            HStack {
                LsStat(value: diffText, label: diff < 0 ? "не хватает до нормы" : "сверх нормы за месяц", tint: diff < 0 ? .red : .primary)
                LsStat(value: "\(s.days)", label: "дней на работе" + extra)
            }
        }
    }

    private func row(_ k: String) -> some View {
        let d = day(k)
        let w = lsWeekday(k)
        let weekend = lsIsWeekend(k)
        let isToday = k == Fmt.today
        let times = (d.inT.isEmpty && d.outT.isEmpty) ? "" : (d.inT.isEmpty ? "—" : d.inT) + " — " + (d.outT.isEmpty ? "—" : d.outT)
        return Button { dayRef = LsDayRef(id: k) } label: {
            HStack(spacing: 12) {
                VStack(spacing: 0) {
                    Text(String(k.suffix(2).drop(while: { $0 == "0" }))).font(.headline).monospacedDigit()
                    Text(lsWeekdays[w - 1]).font(.caption).foregroundStyle(weekend ? Color.red : Color.secondary)
                }
                .frame(width: 36)
                VStack(alignment: .leading, spacing: 3) {
                    if d.type.isEmpty {
                        Text(times.isEmpty ? "—" : times).foregroundStyle(times.isEmpty ? Color.secondary : Color.primary)
                    } else {
                        HStack(spacing: 6) {
                            Badge(text: lsDayTypeNames[d.type] ?? d.type, color: typeColor(d.type))
                            Text(times).font(.footnote).foregroundStyle(.secondary).monospacedDigit()
                        }
                    }
                    if !d.note.isEmpty { Text(d.note).font(.footnote).foregroundStyle(.secondary).lineLimit(1) }
                }
                Spacer(minLength: 8)
                if d.hours > 0 { Text(lsHM(d.hours)).font(.body.weight(.semibold)).monospacedDigit() }
            }
            .frame(minHeight: 44)
            .foregroundStyle(.primary)
        }
        .listRowBackground(rowBackground(today: isToday, weekend: weekend))
    }

    private func rowBackground(today: Bool, weekend: Bool) -> Color {
        if today { return Color.pto.opacity(0.14) }
        return weekend ? theme.control() : theme.panel()
    }

    private func typeColor(_ t: String) -> Color {
        switch t {
        case "Раб": return .green
        case "Вых": return .orange
        case "Отп": return .blue
        case "Бол": return .red
        default: return .purple
        }
    }

    // MARK: Запись

    private func write(_ updates: [String: LsDay]) {
        var all = store.kv("tab") ?? .o([:])
        if case .o = all {} else { all = .o([:]) }
        var month = all[ym] ?? .o([:])
        if case .o = month {} else { month = .o([:]) }
        for (k, d) in updates { month[k] = d.json }
        all[ym] = month
        store.setKV("tab", all)
    }

    private func clockIn() {
        var d = day(Fmt.today)
        if d.type.isEmpty { d.type = "Раб" }
        d.inT = lsNowHM()
        write([Fmt.today: d])
        LsHaptic.success()
        toast("Приход записан: " + d.inT)
    }

    private func clockOut() {
        var d = day(Fmt.today)
        if d.type.isEmpty { d.type = "Раб" }
        d.outT = lsNowHM()
        if d.inT.isEmpty { d.inT = cfg.start }
        write([Fmt.today: d])
        LsHaptic.success()
        toast("Уход записан: " + d.outT + ", отработано " + lsHM(d.hours))
    }

    private func fillWeekdays() {
        let c = cfg
        var updates: [String: LsDay] = [:]
        for k in days where !lsIsWeekend(k) && day(k).isEmpty {
            var d = LsDay(lunch: c.lunch)
            d.type = "Раб"; d.inT = c.start; d.outT = c.end
            updates[k] = d
        }
        if !updates.isEmpty { write(updates); LsHaptic.success() }
        toast(updates.isEmpty ? "Пустых будней нет" : "Заполнено дней: \(updates.count)")
    }

    private func toast(_ text: String) {
        withAnimation { message = text }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { withAnimation { message = nil } }
    }

    // MARK: Выгрузка

    private var csv: LsCSV {
        let c = cfg
        let s = stats
        var rows: [[String]] = [
            ["Табель учёта рабочего времени"],
            ["Сотрудник: " + (store.kv("name").str), title],
            ["Норма, ч в день", lsPlain(c.norm)],
            [],
            ["Дата", "День", "Тип", "Приход", "Уход", "Обед, мин", "Часы", "Сверх нормы", "Примечание"]
        ]
        for k in days {
            let d = day(k), h = d.hours
            let over = d.type == "Раб" ? max(0, h - c.norm) : 0
            rows.append([Fmt.show(k), lsWeekdays[lsWeekday(k) - 1], lsDayTypeNames[d.type] ?? "", d.inT, d.outT,
                         lsPlain(d.lunch), lsPlain((h * 100).rounded() / 100), lsPlain((over * 100).rounded() / 100), d.note])
        }
        rows.append(["Итого", "", "", "", "", "", lsPlain((s.hours * 100).rounded() / 100), lsPlain((s.over * 100).rounded() / 100), ""])
        rows.append([])
        rows.append(["Норма за месяц, ч", lsPlain(s.norm)])
        rows.append(["Отработано, ч", lsPlain((s.hours * 100).rounded() / 100)])
        rows.append(["Разница с нормой, ч", lsPlain(((s.hours - s.norm) * 100).rounded() / 100)])
        rows.append(["Дней на работе", "\(s.days)"])
        rows.append(["Часов в выходные", lsPlain((s.weekend * 100).rounded() / 100)])
        rows.append(["Дней отпуска", "\(days.filter { day($0).type == "Отп" }.count)"])
        rows.append(["Дней больничного", "\(days.filter { day($0).type == "Бол" }.count)"])
        return LsCSV(name: "Табель_\(ym).csv", rows: rows)
    }
}

// MARK: - Лист дня

private struct LsTimeRow: View {
    let title: String
    @Binding var value: String

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            if lsMinutes(value) != nil {
                DatePicker(title, selection: dateBinding, displayedComponents: .hourAndMinute).labelsHidden()
                Button { value = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                    .buttonStyle(.borderless).accessibilityLabel("Убрать время")
            } else {
                Button("Указать") { value = lsNowHM() }.buttonStyle(.borderless)
            }
        }
        .frame(minHeight: 44)
    }

    private var dateBinding: Binding<Date> {
        Binding<Date>(
            get: { lsTimeFormat.date(from: value) ?? Date() },
            set: { value = lsTimeFormat.string(from: $0) })
    }
}

private struct LsDaySheet: View {
    let key: String
    let cfg: LsTabCfg
    let onSave: (LsDay) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var day: LsDay

    init(key: String, day: LsDay, cfg: LsTabCfg, onSave: @escaping (LsDay) -> Void) {
        self.key = key; self.cfg = cfg; self.onSave = onSave
        _day = State(initialValue: day)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Тип дня") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(lsDayTypes, id: \.self) { t in
                                Chip(title: lsDayTypeNames[t] ?? t, on: day.type == t) { pick(t) }
                            }
                        }
                    }
                }
                Section {
                    LsTimeRow(title: "Приход", value: $day.inT)
                    LsTimeRow(title: "Уход", value: $day.outT)
                    Stepper("Обед, мин: \(Int(day.lunch))", value: $day.lunch, in: 0...240, step: 5)
                    LabeledContent("Часы", value: day.hours > 0 ? lsHM(day.hours) : "—")
                }
                Section("Заметка") { TextField("…", text: $day.note) }
                Section {
                    Button("Очистить день", role: .destructive) { day = LsDay(lunch: cfg.lunch) }
                }
            }
            .navigationTitle(Fmt.show(key))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Готово") { onSave(day); LsHaptic.success(); dismiss() }.bold()
                }
            }
            .ptoScreen()
        }
    }

    private func pick(_ t: String) {
        day.type = day.type == t ? "" : t
        if (day.type == "Раб" || day.type == "Ком") && day.inT.isEmpty && day.outT.isEmpty {
            day.inT = cfg.start; day.outT = cfg.end; day.lunch = cfg.lunch
        }
        LsHaptic.tap()
    }
}

// MARK: - Правила табеля

private struct LsRulesSheet: View {
    let onSave: (LsTabCfg) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var cfg: LsTabCfg

    init(cfg: LsTabCfg, onSave: @escaping (LsTabCfg) -> Void) {
        self.onSave = onSave
        _cfg = State(initialValue: cfg)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Stepper("Норма, часов в день: \(Fmt.num(cfg.norm, 1))", value: $cfg.norm, in: 1...24, step: 0.5)
                    LsTimeRow(title: "Начало дня", value: $cfg.start)
                    LsTimeRow(title: "Конец дня", value: $cfg.end)
                    Stepper("Обед по умолчанию, мин: \(Int(cfg.lunch))", value: $cfg.lunch, in: 0...240, step: 5)
                } footer: {
                    Text("Норма месяца считается по будням календаря (без праздников).")
                }
            }
            .navigationTitle("Правила табеля")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Готово") { onSave(cfg); dismiss() }.bold()
                }
            }
            .ptoScreen()
        }
    }
}
