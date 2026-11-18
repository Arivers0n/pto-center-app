import SwiftUI

// MARK: - Трубы и диаметры — та же таблица, что в веб-версии

struct PipeSize: Hashable { let dn: Int; let od: Double }
struct PipeType { let name: String; let short: String; let list: [PipeSize] }

private func sizes(_ a: [(Int, Double)]) -> [PipeSize] { a.map { PipeSize(dn: $0.0, od: $0.1) } }

let pipeTypes: [PipeType] = [
    PipeType(name: "Сталь", short: "ст.", list: sizes([(15, 21.3), (20, 26.9), (25, 33.7), (32, 42.4), (40, 48.3), (50, 57), (65, 76), (80, 89), (100, 108), (125, 133), (150, 159), (200, 219), (250, 273), (300, 325), (350, 377), (400, 426)])),
    PipeType(name: "Нержавейка", short: "нерж.", list: sizes([(10, 14), (15, 18), (20, 25), (25, 32), (32, 38), (40, 42.4), (40, 48.3), (50, 57), (65, 76.1), (80, 89), (100, 104), (100, 108), (125, 133), (150, 159), (200, 219.1), (250, 273), (300, 323.9), (400, 426)])),
    PipeType(name: "ППР", short: "ППР", list: sizes([(15, 20), (20, 25), (25, 32), (32, 40), (40, 50), (50, 63), (65, 75), (80, 90), (100, 110)])),
    PipeType(name: "Канализация", short: "кан.", list: sizes([(40, 50), (50, 63), (80, 90), (100, 110), (150, 160), (200, 200)])),
    PipeType(name: "Медь", short: "медь", list: sizes([(10, 12), (12, 15), (15, 18), (20, 22), (25, 28), (32, 35), (40, 42), (50, 54)]))
]
let dnInch: [Int: Double] = [15: 0.5, 20: 0.75, 25: 1, 32: 1.25, 40: 1.5, 50: 2, 65: 2.5, 80: 3, 100: 4, 125: 5, 150: 6, 200: 8, 250: 10, 300: 12]

func inchText(_ v: Double) -> String { ([0.5: "½", 0.75: "¾", 1.25: "1¼", 1.5: "1½", 2.5: "2½"][v] ?? Fmt.num(v)) + "″" }
func odText(_ v: Double) -> String { Fmt.num(v, 1) }

/// Подпись диаметра как в вебе: «ст. Ø57 · DN50» или для старых записей «DN50 · 2″»
func diameterLabel(_ j: JSON) -> String {
    if let od = j["od"].num {
        let t = pipeTypes.first { $0.name == j["pipe"].str }
        let prefix = t.map { $0.short + " " } ?? ""
        let dn = j["dn"].num.map { " · DN\(Int($0))" } ?? ""
        return prefix + "Ø" + odText(od) + dn
    }
    if let inch = j["inch"].num {
        let dn = dnInch.first { $0.value == inch }?.key
        return (dn.map { "DN\($0) · " } ?? "") + inchText(inch)
    }
    return "—"
}

// MARK: - Журнал: смены по дням

struct KsShift: Identifiable {
    let id: String
    let lines: [Rec]
    var first: Rec { lines[0] }
    var meters: Double { lines.reduce(0) { $0 + ($1["m"].num ?? 0) } }
    var pieces: Double { lines.reduce(0) { $0 + ($1["pcs"].num ?? 0) } }
}

private enum KsJournalSheet: Identifiable {
    case new, edit([String]), copy([String]), report(String)
    var id: String {
        switch self {
        case .new: return "new"
        case .edit(let i): return "edit-" + i.joined(separator: ",")
        case .copy(let i): return "copy-" + i.joined(separator: ",")
        case .report(let d): return "report-" + d
        }
    }
}

private func ksSizeKey(_ r: Rec) -> Double { r["od"].num ?? r["inch"].num ?? 0 }

/// Одна смена = записи с общим batch; у старых записей — одна дата, бригада, система и участок
func ksShifts(_ recs: [Rec]) -> [KsShift] {
    let byKey = Dictionary(grouping: recs) { (j: Rec) -> String in
        j["batch"].str.isEmpty ? [j["date"].str, j["brigade"].str, j["system"].str, j["place"].str].joined(separator: "|") : j["batch"].str
    }
    return byKey.map { (key: String, lines: [Rec]) -> KsShift in
        KsShift(id: key, lines: lines.sorted { ksSizeKey($0) > ksSizeKey($1) })
    }
}

struct JournalView: View {
    @EnvironmentObject var store: Store
    @State private var query = ""
    @State private var sheet: KsJournalSheet?
    @State private var deleting: KsShift?

    private var days: [(day: String, shifts: [KsShift])] {
        let q = query.lowercased().trimmingCharacters(in: .whitespaces)
        let all = store.list("journal").filter { j in
            q.isEmpty || [j["brigade"].str, j["system"].str, j["place"].str, diameterLabel(j.v), Fmt.show(j["date"].str)].joined(separator: " ").lowercased().contains(q)
        }
        let byDay = Dictionary(grouping: ksShifts(all)) { (s: KsShift) -> String in s.first["date"].str }
        var out: [(day: String, shifts: [KsShift])] = []
        for (day, list) in byDay {
            let sorted = list.sorted { ($0.first["brigade"].str, $0.first["system"].str) < ($1.first["brigade"].str, $1.first["system"].str) }
            out.append((day: day, shifts: sorted))
        }
        return out.sorted { $0.day > $1.day }
    }

    var body: some View {
        let recs = store.list("journal")
        let totalM = recs.reduce(0) { $0 + ($1["m"].num ?? 0) }
        let totalP = recs.reduce(0) { $0 + ($1["pcs"].num ?? 0) }
        List {
            if !recs.isEmpty {
                Section {
                    HStack {
                        Text("Всего за всё время").foregroundStyle(.secondary)
                        Spacer()
                        Text(Fmt.num(totalM, 1) + " м" + (totalP > 0 ? " · " + Fmt.num(totalP, 0) + " шт." : "")).font(.headline).monospacedDigit()
                    }
                }
            }
            ForEach(days, id: \.day) { group in
                Section {
                    ForEach(group.shifts) { sh in shiftRow(sh) }
                } header: {
                    dayHeader(group.day, group.shifts)
                }
            }
            if days.isEmpty {
                EmptyNote(title: query.isEmpty ? "Смен пока нет" : "Ничего не найдено",
                          text: query.isEmpty ? "Нажмите «+», чтобы записать, что бригада смонтировала за смену." : "Ищите по бригаде, системе, участку или диаметру.")
            }
        }
        .listStyle(.insetGrouped)
        .ksColumn().ptoScreen()
        .searchable(text: $query, prompt: "Бригада, система, участок, диаметр")
        .navigationTitle("Журнал прораба")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                KsCSVShare(title: "В Excel", fileName: "Журнал_прораба.csv", rows: csvRows())
                Button { sheet = .report(Fmt.today) } label: { Image(systemName: "doc.text") }.accessibilityLabel("Отчёт за смену")
                Button { sheet = .new } label: { Image(systemName: "plus") }.accessibilityLabel("Записать смену")
            }
        }
        .sheet(item: $sheet) { s in
            switch s {
            case .new: NavigationStack { NewShiftView() }
            case .edit(let ids): NavigationStack { NewShiftView(editing: records(ids)) }
            case .copy(let ids): NavigationStack { NewShiftView(editing: records(ids), copy: true) }
            case .report(let d): KsReportView(date: d)
            }
        }
        .confirmationDialog("Удалить смену целиком?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
            Button("Удалить смену", role: .destructive) {
                if let d = deleting { withAnimation { d.lines.forEach { store.delete("journal", $0.id) } } }
            }
            Button("Отмена", role: .cancel) {}
        }
        .refreshable { await store.sync() }
    }

    private func records(_ ids: [String]) -> [Rec] { ids.compactMap { store.get("journal", $0) } }

    private func dayHeader(_ day: String, _ shifts: [KsShift]) -> some View {
        let m = shifts.reduce(0) { $0 + $1.meters }
        let p = shifts.reduce(0) { $0 + $1.pieces }
        return HStack {
            Text(Fmt.date(day).map { Fmt.ruLong.string(from: $0) } ?? day)
            Spacer()
            Text(Fmt.num(m, 1) + " м" + (p > 0 ? " · " + Fmt.num(p, 0) + " шт." : "")).monospacedDigit()
            Button { sheet = .report(day) } label: { Image(systemName: "doc.text").frame(minWidth: 32, minHeight: 32) }
                .buttonStyle(.borderless).accessibilityLabel("Отчёт за этот день")
        }
        .textCase(nil)
    }

    @ViewBuilder private func shiftRow(_ sh: KsShift) -> some View {
        let ids = sh.lines.map { $0.id }
        Button { sheet = .edit(ids) } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(sh.first["brigade"].str).font(.headline)
                    if !sh.first["system"].str.isEmpty { Badge(text: sh.first["system"].str, color: .pto) }
                    Spacer()
                    Text(Fmt.num(sh.meters, 1) + " м").font(.headline).monospacedDigit()
                }
                if !sh.first["place"].str.isEmpty { Text(sh.first["place"].str).font(.subheadline).foregroundStyle(.secondary) }
                ForEach(sh.lines) { l in
                    let pcs = l["pcs"].num ?? 0
                    let tail = pcs > 0 ? " · \(Fmt.num(pcs, 0)) шт." : ""
                    HStack {
                        Text(diameterLabel(l.v)).font(.subheadline)
                        Spacer()
                        Text("\(Fmt.num(l["m"].num ?? 0, 1)) м\(tail)").font(.subheadline).foregroundStyle(.secondary).monospacedDigit()
                    }
                }
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .swipeActions {
            Button(role: .destructive) { deleting = sh } label: { Label("Удалить смену", systemImage: "trash") }
            Button { sheet = .copy(ids) } label: { Label("Повторить", systemImage: "doc.on.doc") }.tint(.blue)
        }
        .contextMenu {
            Button { sheet = .edit(ids) } label: { Label("Изменить", systemImage: "pencil") }
            Button { sheet = .copy(ids) } label: { Label("Записать похожую смену", systemImage: "doc.on.doc") }
            Button(role: .destructive) { deleting = sh } label: { Label("Удалить смену", systemImage: "trash") }
        }
    }

    /// Те же колонки, что в «В Excel» веб-версии
    private func csvRows() -> [[String]] {
        var rows = [["Дата", "Бригада", "Система", "Участок", "Труба", "Ø наружный, мм", "DN", "Дюйм", "Метров", "Шт"]]
        for j in store.list("journal").sorted(by: { $0["date"].str < $1["date"].str }) {
            let inch = j["inch"].num
            let dn: Int? = j["dn"].num.map { Int($0) } ?? inch.flatMap { i in dnInch.first { $0.value == i }?.key }
            let inchOut: Double? = inch ?? dn.flatMap { dnInch[$0] }
            rows.append([Fmt.show(j["date"].str), j["brigade"].str, j["system"].str, j["place"].str, j["pipe"].str,
                         j["od"].num.map { KsNum.flatText($0) } ?? "", dn.map { String($0) } ?? "",
                         inchOut.map { KsNum.flatText($0) } ?? "", KsNum.flatText(j["m"].num ?? 0), KsNum.flatText(j["pcs"].num ?? 0)])
        }
        return rows
    }
}

// MARK: - Отчёт за смену (текст как в веб-версии)

struct KsShiftMeta: Equatable {
    var weather = ""
    var people = ""
    var delay = ""
    var brief = ""
    var safe = true
    init() {}
    init(_ j: JSON?) {
        weather = j?["weather"].str ?? ""
        people = j?["people"].str ?? ""
        delay = j?["delay"].str ?? ""
        brief = j?["brief"].str ?? ""
        if let sv = j?["safe"], case .b(let b) = sv { safe = b }
    }
}

private struct KsReportItem {
    var brigade: String
    var system: String
    var place: String
    var label: String
    var m: Double
    var n: Double
    var text: String { label + " — " + Fmt.num(m, 1) + " м" + (n > 0 ? " (" + Fmt.num(n, 0) + " шт.)" : "") }
}

private func ksReportItems(_ day: [Rec]) -> [KsReportItem] {
    var order: [String] = []
    var by: [String: KsReportItem] = [:]
    for j in day {
        let label = diameterLabel(j.v)
        let key = [j["brigade"].str, j["system"].str, j["place"].str, label].joined(separator: "|")
        if by[key] == nil {
            order.append(key)
            by[key] = KsReportItem(brigade: j["brigade"].str, system: j["system"].str, place: j["place"].str, label: label, m: 0, n: 0)
        }
        by[key]?.m += j["m"].num ?? 0
        by[key]?.n += j["pcs"].num ?? 0
    }
    return order.compactMap { by[$0] }
}

private func ksReportBrigades(_ items: [KsReportItem]) -> [String] {
    var out: [String] = []
    for it in items where !out.contains(it.brigade) { out.append(it.brigade) }
    return out
}

private func ksReportLines(_ items: [KsReportItem], brigade b: String) -> [String] {
    var keys: [String] = []
    var groups: [String: [KsReportItem]] = [:]
    for it in items where it.brigade == b {
        let k = it.system + "|" + it.place
        if groups[k] == nil { keys.append(k) }
        groups[k, default: []].append(it)
    }
    var out: [String] = []
    for k in keys {
        guard let a = groups[k], let o = a.first else { continue }
        let head = "• " + o.system + (o.place.isEmpty ? "" : ", " + o.place)
        if a.count == 1 {
            out.append(head + ": " + o.text)
        } else {
            out.append(head + " — " + Fmt.num(a.reduce(0) { $0 + $1.m }, 1) + " м:")
            a.forEach { out.append("    " + $0.text) }
        }
    }
    return out
}

func ksShiftReport(_ store: Store, date: String, meta m: KsShiftMeta) -> String {
    let day = store.list("journal").filter { $0["date"].str == date }
    let items = ksReportItems(day)
    var out = ["Отчёт за смену " + Fmt.show(date)]
    if !m.weather.isEmpty { out.append("Погода: " + m.weather) }
    if !m.people.isEmpty { out.append("Людей на объекте: " + m.people) }
    for b in ksReportBrigades(items) {
        out.append("")
        out.append(b + ":")
        out += ksReportLines(items, brigade: b)
    }
    let tm = day.reduce(0) { $0 + ($1["m"].num ?? 0) }
    let tp = day.reduce(0) { $0 + ($1["pcs"].num ?? 0) }
    out.append("")
    out.append(day.isEmpty ? "За этот день записей в журнале нет." : "Итого: " + Fmt.num(tm, 1) + " м" + (tp > 0 ? ", " + Fmt.num(tp, 0) + " шт." : ""))
    let openIssues = store.list("issues").filter { !["Закрыто", "Устранено"].contains($0["status"].str) }
    let overdue = openIssues.filter { !$0["due"].str.isEmpty && $0["due"].str < date }.count
    if !openIssues.isEmpty { out.append("Открытых замечаний: \(openIssues.count)" + (overdue > 0 ? ", просрочено \(overdue)" : "")) }
    if !m.delay.isEmpty { out.append("Задержки и проблемы: " + m.delay) }
    let waiting = store.list("requests").filter { $0["st"].str == "Заказано" }
    if !waiting.isEmpty {
        let parts = waiting.map { "заявка №" + $0["no"].str + ($0["eta"].str.isEmpty ? "" : " (к " + Fmt.show($0["eta"].str) + ")") }
        out.append("Ждём поставку: " + parts.joined(separator: ", "))
    }
    out.append(m.safe ? "Охрана труда: происшествий нет" + (m.brief.isEmpty ? "" : ", " + m.brief) : "Охрана труда: были происшествия, см. примечание")
    if let d = Fmt.date(date), let next = Calendar.current.date(byAdding: .day, value: 1, to: d) {
        let tk = Fmt.iso.string(from: next)
        let plan = store.list("tasks").filter { !($0["done"]?.bool ?? false) && $0["due"] != nil && $0["due"].str <= tk }
        if !plan.isEmpty {
            out.append("")
            out.append("На завтра:")
            plan.prefix(6).forEach { out.append("• " + $0["text"].str) }
        }
    }
    return out.joined(separator: "\n")
}

struct KsReportView: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    @State private var date: Date
    @State private var loadedDay: String
    @State private var meta = KsShiftMeta()

    init(date day: String) {
        let ok = Fmt.date(day) != nil
        _date = State(initialValue: Fmt.date(day) ?? Date())
        _loadedDay = State(initialValue: ok ? String(day.prefix(10)) : Fmt.today)
    }

    private var day: String { Fmt.iso.string(from: date) }
    private var text: String { ksShiftReport(store, date: day, meta: meta) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("Дата", selection: $date, displayedComponents: .date).environment(\.locale, Locale(identifier: "ru_RU"))
                    TextField("Погода, например −5 °C, снег", text: $meta.weather)
                    TextField("Людей на объекте", text: $meta.people).keyboardType(.numberPad)
                    TextField("Задержки и проблемы", text: $meta.delay)
                    TextField("Инструктаж по охране труда: тема", text: $meta.brief)
                    Toggle("Были происшествия по охране труда", isOn: Binding(get: { !meta.safe }, set: { meta.safe = !$0 }))
                } footer: { Text("Текст собран из журнала прораба, заявок, замечаний и задач. Отправьте его в мессенджер.") }
                Section("Текст отчёта") {
                    Text(text).font(.system(.footnote, design: .monospaced)).textSelection(.enabled)
                }
            }
            .navigationTitle("Отчёт за смену")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Закрыть") { saveMeta(); dismiss() } }
                ToolbarItem(placement: .primaryAction) { ShareLink(item: text) { Image(systemName: "square.and.arrow.up") } }
            }
            .onAppear { meta = KsShiftMeta(store.kv("shiftMeta")?[loadedDay]) }
            .onChange(of: date) { _ in
                saveMeta()
                loadedDay = day
                meta = KsShiftMeta(store.kv("shiftMeta")?[loadedDay])
            }
            .onDisappear { saveMeta() }
        }
    }

    private func saveMeta() {
        var all = store.kv("shiftMeta")?.obj ?? [:]
        var entry = all[loadedDay]?.obj ?? [:]
        entry["weather"] = JSON.s(meta.weather)
        entry["people"] = JSON.s(meta.people)
        entry["delay"] = JSON.s(meta.delay)
        entry["brief"] = JSON.s(meta.brief)
        entry["safe"] = JSON.b(meta.safe)
        let json = JSON.o(entry)
        guard all[loadedDay] != json else { return }
        all[loadedDay] = json
        store.setKV("shiftMeta", JSON.o(all))
    }
}

// MARK: - Запись и правка смены: бригада, система, участок и все диаметры за день

struct ShiftLine: Identifiable {
    let id = UUID()
    var pipe = "Сталь"
    var size: PipeSize?
    var m = ""
    var pcs = ""
    var recID: String?
    var legacy = false

    init(pipe: String = "Сталь") { self.pipe = pipe }

    init(rec: Rec, keepAmounts: Bool) {
        pipe = rec["pipe"].str.isEmpty ? "Сталь" : rec["pipe"].str
        if let od = rec["od"].num {
            size = PipeSize(dn: Int(rec["dn"].num ?? 0), od: od)
        } else if let inch = rec["inch"].num, let dn = dnInch.first(where: { $0.value == inch })?.key {
            size = pipeTypes.first?.list.first { $0.dn == dn }
            legacy = size == nil
        } else {
            legacy = true
        }
        if keepAmounts {
            recID = rec.id
            m = KsNum.flatText(rec["m"].num ?? 0)
            let p = rec["pcs"].num ?? 0
            pcs = p > 0 ? KsNum.flatText(p) : ""
        }
    }
}

struct NewShiftView: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    private let editing: [Rec]
    private let isNew: Bool
    @State private var date: Date
    @State private var brigade: String
    @State private var system: String
    @State private var place: String
    @State private var lines: [ShiftLine]

    init(editing recs: [Rec]? = nil, copy: Bool = false) {
        isNew = recs == nil || copy
        editing = copy ? [] : (recs ?? [])
        if let recs, let f = recs.first {
            _date = State(initialValue: copy ? Date() : (Fmt.date(f["date"].str) ?? Date()))
            _brigade = State(initialValue: f["brigade"].str)
            _system = State(initialValue: f["system"].str)
            _place = State(initialValue: f["place"].str)
            _lines = State(initialValue: recs.map { ShiftLine(rec: $0, keepAmounts: !copy) })
        } else {
            _date = State(initialValue: Date())
            _brigade = State(initialValue: "")
            _system = State(initialValue: "")
            _place = State(initialValue: "")
            _lines = State(initialValue: [ShiftLine()])
        }
    }

    private static let defaultBrigades = ["Бригада 1", "Бригада 2", "Бригада 3", "Бригада 4"]
    private static let defaultSystems = ["В1.1", "В1", "Т3", "Т4", "В1вд", "Т3вд", "К1", "К2", "К3"]

    private func options(_ defaults: [String], _ key: String) -> [String] {
        var seen = Set<String>()
        return (defaults + store.list("journal").map { $0[key].str }).filter { !$0.isEmpty && seen.insert($0).inserted }
    }
    private func amount(_ s: String) -> Double { KsNum.parse(s) ?? 0 }
    private func counted(_ l: ShiftLine) -> Bool { amount(l.m) > 0 || amount(l.pcs) > 0 }
    private var valid: Bool {
        let used = lines.filter(counted)
        return !brigade.trimmingCharacters(in: .whitespaces).isEmpty && !used.isEmpty && used.allSatisfy { $0.size != nil || $0.recID != nil }
    }

    var body: some View {
        Form {
            Section("Смена") {
                DatePicker("Дата", selection: $date, displayedComponents: .date)
                Suggest(title: "Бригада", text: $brigade, options: options(Self.defaultBrigades, "brigade"))
                Suggest(title: "Система", text: $system, options: options(Self.defaultSystems, "system"))
                TextField("Участок / оси", text: $place, axis: .vertical)
            }
            ForEach(Array(lines.indices), id: \.self) { i in lineSection(i) }
            Section {
                Button { withAnimation { lines.append(ShiftLine(pipe: lines.last?.pipe ?? "Сталь")) } } label: { Label("Ещё диаметр", systemImage: "plus.circle.fill") }
                let sum = lines.reduce(0) { $0 + amount($1.m) }
                if sum > 0 { Text("В смене: \(Fmt.num(sum, 1)) м").foregroundStyle(.secondary).monospacedDigit() }
            } footer: { Text("Бригада за смену может смонтировать несколько диаметров — добавьте каждый.") }
        }
        .environment(\.locale, Locale(identifier: "ru_RU"))
        .navigationTitle(isNew ? "Записать смену" : "Правка смены")
        .navigationBarTitleDisplayMode(.inline)
        .scrollDismissesKeyboard(.interactively)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) { Button(isNew ? "Записать" : "Сохранить") { save() }.disabled(!valid) }
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Готово") { UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil) }
            }
        }
        .onAppear {
            guard editing.isEmpty, brigade.isEmpty, system.isEmpty,
                  let last = store.list("journal").max(by: { $0["date"].str < $1["date"].str }) else { return }
            brigade = last["brigade"].str
            system = last["system"].str
        }
    }

    @ViewBuilder private func lineSection(_ i: Int) -> some View {
        if i < lines.count {
            Section {
                Picker("Труба", selection: Binding(get: { lines.indices.contains(i) ? lines[i].pipe : "Сталь" },
                                                   set: { if lines.indices.contains(i) { lines[i].pipe = $0; lines[i].size = nil } })) {
                    ForEach(pipeTypes, id: \.name) { Text($0.name).tag($0.name) }
                }
                Picker("Диаметр", selection: line(i, \.size, nil)) {
                    Text("Выберите").tag(PipeSize?.none)
                    ForEach(sizeOptions(lines[i]), id: \.self) { d in
                        Text("Ø" + odText(d.od) + " · DN\(d.dn)").tag(PipeSize?.some(d))
                    }
                }
                HStack {
                    TextField("Метров", text: line(i, \.m, "")).keyboardType(.decimalPad)
                    Divider()
                    TextField("Штук", text: line(i, \.pcs, "")).keyboardType(.numberPad)
                }
                if lines[i].legacy {
                    Text("Старая запись с диаметром в дюймах: выберите диаметр заново или оставьте как есть.").font(.caption).foregroundStyle(.secondary)
                }
            } header: {
                HStack {
                    Text("Диаметр \(i + 1)")
                    Spacer()
                    if lines.count > 1 { Button("Убрать", role: .destructive) { withAnimation { _ = lines.remove(at: i) } }.font(.caption) }
                }
            }
        }
    }

    private func sizeOptions(_ l: ShiftLine) -> [PipeSize] {
        var list = pipeTypes.first { $0.name == l.pipe }?.list ?? []
        if let s = l.size, !list.contains(s) { list.append(s) }
        return list
    }

    /// Привязка к строке, которая не падает, если строку только что убрали
    private func line<T>(_ i: Int, _ kp: WritableKeyPath<ShiftLine, T>, _ fallback: T) -> Binding<T> {
        Binding(get: { lines.indices.contains(i) ? lines[i][keyPath: kp] : fallback },
                set: { if lines.indices.contains(i) { lines[i][keyPath: kp] = $0 } })
    }

    private func save() {
        let oldBatch = editing.first?["batch"].str ?? ""
        let batch = oldBatch.isEmpty ? Fmt.uid() : oldBatch
        let d = Fmt.iso.string(from: date)
        let head: [String: JSON] = ["batch": .s(batch), "date": .s(d), "brigade": .s(brigade.trimmingCharacters(in: .whitespaces)),
                                    "system": .s(system.trimmingCharacters(in: .whitespaces)), "place": .s(place.trimmingCharacters(in: .whitespaces))]
        var keep = Set<String>()
        for l in lines where counted(l) {
            var v = head
            v["m"] = .n(amount(l.m))
            v["pcs"] = .n(amount(l.pcs))
            if let size = l.size {
                v["pipe"] = .s(l.pipe)
                v["od"] = .n(size.od)
                v["dn"] = .n(Double(size.dn))
                v["inch"] = dnInch[size.dn].map { JSON.n($0) } ?? .null
            }
            if let rid = l.recID, var r = store.get("journal", rid) {
                for (k, x) in v { r.v[k] = x }
                store.put("journal", r)
                keep.insert(rid)
            } else if l.size != nil {
                v["note"] = .s("")
                store.put("journal", Rec(id: Fmt.uid(), v: .o(v)))
            }
        }
        for r in editing where !keep.contains(r.id) { store.delete("journal", r.id) }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        dismiss()
    }
}

/// Поле с подсказками из прошлых записей
struct Suggest: View {
    let title: String
    @Binding var text: String
    let options: [String]
    var body: some View {
        HStack {
            TextField(title, text: $text)
            if !options.isEmpty {
                Menu {
                    ForEach(options, id: \.self) { o in Button(o) { text = o } }
                } label: { Image(systemName: "chevron.down.circle").foregroundStyle(.secondary).frame(minWidth: 32, minHeight: 32) }
                .accessibilityLabel("\(title): выбрать из списка")
            }
        }
    }
}
