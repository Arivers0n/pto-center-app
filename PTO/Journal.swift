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

private struct Shift: Identifiable {
    let id: String
    let lines: [Rec]
    var first: Rec { lines[0] }
    var meters: Double { lines.reduce(0) { $0 + ($1["m"].num ?? 0) } }
}

struct JournalView: View {
    @EnvironmentObject var store: Store
    @State private var newShift = false
    @State private var query = ""

    private var days: [(day: String, shifts: [Shift])] {
        let q = query.lowercased()
        let all = store.list("journal").filter { j in
            q.isEmpty || [j["brigade"].str, j["system"].str, j["place"].str, diameterLabel(j.v)].joined(separator: " ").lowercased().contains(q)
        }
        let byShift = Dictionary(grouping: all) { j -> String in j["batch"].str.isEmpty ? j.id : j["batch"].str }
        let size: (Rec) -> Double = { $0["od"].num ?? $0["inch"].num ?? 0 }
        let shifts: [Shift] = byShift.map { (key, lines) in Shift(id: key, lines: lines.sorted { size($0) > size($1) }) }
        let byDay = Dictionary(grouping: shifts) { (s: Shift) -> String in s.first["date"].str }
        var out: [(day: String, shifts: [Shift])] = []
        for (day, list) in byDay { out.append((day: day, shifts: list.sorted { $0.first["brigade"].str < $1.first["brigade"].str })) }
        return out.sorted { $0.day > $1.day }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(days, id: \.day) { group in
                    Section {
                        ForEach(group.shifts) { sh in shiftRow(sh) }
                    } header: {
                        HStack {
                            Text(Fmt.date(group.day).map { Fmt.ruLong.string(from: $0) } ?? group.day)
                            Spacer()
                            Text(Fmt.num(group.shifts.reduce(0) { $0 + $1.meters }, 1) + " м").monospacedDigit()
                        }
                    }
                }
                if days.isEmpty { EmptyNote(title: "Смен пока нет", text: "Нажмите «+», чтобы записать, что бригада смонтировала за смену.") }
            }
            .searchable(text: $query, prompt: "Бригада, система, участок, диаметр")
            .navigationTitle("Журнал прораба")
            .toolbar {
                ToolbarItem(placement: .primaryAction) { Button { newShift = true } label: { Image(systemName: "plus") }.accessibilityLabel("Записать смену") }
            }
            .sheet(isPresented: $newShift) { NavigationStack { NewShiftView() } }
            .refreshable { await store.sync() }
        }
    }

    @ViewBuilder private func shiftRow(_ sh: Shift) -> some View {
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
        .swipeActions {
            Button(role: .destructive) { withAnimation { sh.lines.forEach { store.delete("journal", $0.id) } } } label: { Label("Удалить смену", systemImage: "trash") }
        }
    }
}

// MARK: - Новая смена: бригада, система, участок и все диаметры за день

struct ShiftLine: Identifiable {
    let id = UUID()
    var pipe = "Сталь"
    var size: PipeSize?
    var m = ""
    var pcs = ""
}

struct NewShiftView: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    @State private var date = Date()
    @State private var brigade = ""
    @State private var system = ""
    @State private var place = ""
    @State private var lines = [ShiftLine()]

    private var recentBrigades: [String] { Array(Set(store.list("journal").map { $0["brigade"].str }.filter { !$0.isEmpty })).sorted() }
    private var recentSystems: [String] { Array(Set(store.list("journal").map { $0["system"].str }.filter { !$0.isEmpty })).sorted() }
    private func meters(_ s: String) -> Double { Double(s.replacingOccurrences(of: ",", with: ".")) ?? 0 }
    private var valid: Bool { !brigade.trimmingCharacters(in: .whitespaces).isEmpty && lines.contains { $0.size != nil && meters($0.m) > 0 } }

    var body: some View {
        Form {
            Section("Смена") {
                DatePicker("Дата", selection: $date, displayedComponents: .date)
                Suggest(title: "Бригада", text: $brigade, options: recentBrigades)
                Suggest(title: "Система", text: $system, options: recentSystems)
                TextField("Участок / оси", text: $place, axis: .vertical)
            }
            ForEach(Array(lines.indices), id: \.self) { i in lineSection(i) }
            Section {
                Button { withAnimation { lines.append(ShiftLine(pipe: lines.last?.pipe ?? "Сталь")) } } label: { Label("Ещё диаметр", systemImage: "plus.circle.fill") }
            } footer: { Text("Бригада за смену может смонтировать несколько диаметров — добавьте каждый.") }
        }
        .environment(\.locale, Locale(identifier: "ru_RU"))
        .navigationTitle("Записать смену")
        .navigationBarTitleDisplayMode(.inline)
        .scrollDismissesKeyboard(.interactively)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) { Button("Записать") { save() }.disabled(!valid) }
        }
        .onAppear {
            if let last = store.list("journal").max(by: { $0["date"].str < $1["date"].str }) {
                if brigade.isEmpty { brigade = last["brigade"].str }
                if system.isEmpty { system = last["system"].str }
            }
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
                    ForEach(pipeTypes.first { $0.name == lines[i].pipe }?.list ?? [], id: \.self) { d in
                        Text("Ø" + odText(d.od) + " · DN\(d.dn)").tag(PipeSize?.some(d))
                    }
                }
                HStack {
                    TextField("Метров", text: line(i, \.m, "")).keyboardType(.decimalPad)
                    Divider()
                    TextField("Штук", text: line(i, \.pcs, "")).keyboardType(.numberPad)
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

    /// Привязка к строке, которая не падает, если строку только что убрали
    private func line<T>(_ i: Int, _ kp: WritableKeyPath<ShiftLine, T>, _ fallback: T) -> Binding<T> {
        Binding(get: { lines.indices.contains(i) ? lines[i][keyPath: kp] : fallback },
                set: { if lines.indices.contains(i) { lines[i][keyPath: kp] = $0 } })
    }

    private func save() {
        let batch = Fmt.uid(), d = Fmt.iso.string(from: date)
        for l in lines {
            guard let size = l.size else { continue }
            let m = meters(l.m)
            guard m > 0 else { continue }
            let v: [String: JSON] = ["batch": .s(batch), "date": .s(d), "brigade": .s(brigade.trimmingCharacters(in: .whitespaces)),
                                     "system": .s(system.trimmingCharacters(in: .whitespaces)), "place": .s(place.trimmingCharacters(in: .whitespaces)),
                                     "pipe": .s(l.pipe), "od": .n(size.od), "dn": .n(Double(size.dn)), "inch": dnInch[size.dn].map { JSON.n($0) } ?? .null,
                                     "m": .n(m), "pcs": .n(Double(l.pcs) ?? 0), "note": .s("")]
            store.put("journal", Rec(id: Fmt.uid(), v: .o(v)))
        }
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
                } label: { Image(systemName: "chevron.down.circle").foregroundStyle(.secondary) }
                .accessibilityLabel("\(title): выбрать из прошлых")
            }
        }
    }
}
