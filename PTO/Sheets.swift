import SwiftUI
import UniformTypeIdentifiers

// MARK: - Описание листов (как SHEETS в вебе)

private enum ClKind { case text, num, calc }
private enum ClFmt { case dec, int, pct, status }

private struct ClCol {
    let k: String
    let label: String
    let kind: ClKind
    var fmt: ClFmt = .dec
    var def: String? = nil
    var bad = false
    var neg = false
    var f: (([String: Double], Double) -> Double)? = nil
}

private struct ClSheet {
    let id: String
    let title: String
    let hint: String
    let cols: [ClCol]
    let sums: Set<String>
    var paramLabel: String? = nil
    var paramDef: Double = 0
    var importLabel: String? = nil
    var extraTotals: [String: ([String: Double]) -> Double] = [:]
    var svod: (key: String, val: String, label: String)? = nil
}

private let clPieceKey = "piece"

private func clShortage(_ o: [String: Double], _ p: Double) -> Double { max(0, (o["need"] ?? 0) - (o["slen"] ?? 0)) }
private func clWithReserve(_ o: [String: Double]) -> Double { ((o["q"] ?? 0) * (1 + (o["z"] ?? 0) / 100) - 1e-9).rounded(.up) }

private let clSheets: [ClSheet] = [
    ClSheet(
        id: "pipes", title: "Трубы: что докупить",
        hint: "Для каждого диаметра: сколько труб нужно по помещениям, сколько лежит на складе и сколько мерных труб нужно докупить.",
        cols: [
            ClCol(k: "d", label: "Ду", kind: .text, def: ""),
            ClCol(k: "need", label: "Нужно по помещениям, м", kind: .num),
            ClCol(k: "stock", label: "На складе, шт мерных", kind: .num, fmt: .int),
            ClCol(k: "slen", label: "Длина склада, м", kind: .calc, f: { o, p in (o["stock"] ?? 0) * p / 1000 }),
            ClCol(k: "short", label: "Не хватает, м", kind: .calc, bad: true, f: { o, p in clShortage(o, p) }),
            ClCol(k: "buy", label: "Докупить, шт мерных", kind: .calc, fmt: .int, bad: true, f: { o, p in
                ((o["short"] ?? 0) * 1000 / p - 1e-9).rounded(.up).clamped0 }),
            ClCol(k: "done", label: "Уже смонтировано, м (справочно)", kind: .num)
        ],
        sums: ["need", "stock", "slen", "short", "buy", "done"],
        paramLabel: "Длина одной мерной трубы, мм", paramDef: 1250,
        importLabel: "Взять «Нужно» из листа «Потребность по помещениям»"),
    ClSheet(
        id: "rooms", title: "Потребность по помещениям",
        hint: "Записывайте, сколько какого диаметра нужно в каждом помещении. Внизу таблица сама сложит длину по диаметрам.",
        cols: [
            ClCol(k: "n", label: "Помещение", kind: .text, def: ""),
            ClCol(k: "d", label: "Ду", kind: .text, def: ""),
            ClCol(k: "l", label: "Длина, м", kind: .num)
        ],
        sums: ["l"], svod: (key: "d", val: "l", label: "Итого по диаметрам")),
    ClSheet(
        id: "vol", title: "Выполнение объёмов",
        hint: "По проекту, сделано, осталось и процент выполнения. Строки можно подтянуть из журнала прораба.",
        cols: [
            ClCol(k: "n", label: "Наименование", kind: .text, def: ""),
            ClCol(k: "u", label: "Ед.", kind: .text, def: "м"),
            ClCol(k: "p", label: "По проекту", kind: .num),
            ClCol(k: "f", label: "Выполнено", kind: .num),
            ClCol(k: "o", label: "Осталось", kind: .calc, neg: true, f: { o, _ in (o["p"] ?? 0) - (o["f"] ?? 0) }),
            ClCol(k: "c", label: "Выполнение", kind: .calc, fmt: .pct, f: { o, _ in
                (o["p"] ?? 0) != 0 ? (o["f"] ?? 0) / (o["p"] ?? 0) : 0 })
        ],
        sums: ["p", "f", "o"], importLabel: "Подтянуть из журнала прораба",
        extraTotals: ["c": { t in (t["p"] ?? 0) != 0 ? (t["f"] ?? 0) / (t["p"] ?? 0) : 0 }]),
    ClSheet(
        id: "tmc", title: "Смета ТМЦ",
        hint: "Количество с запасом (округляется вверх), цена и сумма. Позиции можно взять из заявки.",
        cols: [
            ClCol(k: "n", label: "Наименование", kind: .text, def: ""),
            ClCol(k: "u", label: "Ед.", kind: .text, def: "шт"),
            ClCol(k: "q", label: "Кол-во", kind: .num),
            ClCol(k: "z", label: "Запас, %", kind: .num, def: "5"),
            ClCol(k: "k", label: "К заказу", kind: .calc, fmt: .int, f: { o, _ in clWithReserve(o) }),
            ClCol(k: "pr", label: "Цена, ₽", kind: .num),
            ClCol(k: "s", label: "Сумма, ₽", kind: .calc, f: { o, _ in clWithReserve(o) * (o["pr"] ?? 0) })
        ],
        sums: ["s"], importLabel: "Взять позиции из заявки"),
    ClSheet(
        id: "mat", title: "Остатки давальческих",
        hint: "Получено, израсходовано и что осталось. Данные можно взять из раздела «Материалы».",
        cols: [
            ClCol(k: "n", label: "Наименование", kind: .text, def: ""),
            ClCol(k: "u", label: "Ед.", kind: .text, def: "шт"),
            ClCol(k: "a", label: "Получено", kind: .num),
            ClCol(k: "b", label: "Израсходовано", kind: .num),
            ClCol(k: "l", label: "Осталось", kind: .calc, neg: true, f: { o, _ in (o["a"] ?? 0) - (o["b"] ?? 0) }),
            ClCol(k: "st", label: "Статус", kind: .calc, fmt: .status, f: { o, _ in (o["a"] ?? 0) - (o["b"] ?? 0) })
        ],
        sums: ["a", "b", "l"], importLabel: "Взять из раздела «Материалы»")
]

private extension Double {
    var clamped0: Double { Swift.max(0, self) }
}

// MARK: - Строки

private struct ClRow: Identifiable, Equatable {
    let id = UUID()
    var v: [String: String]
}

private func clDefaultRows(_ id: String) -> [[String: String]] {
    switch id {
    case "vol":
        return [["n": "Трубопроводы В1", "u": "м", "p": "1200", "f": "850"],
                ["n": "Трубопроводы Т3", "u": "м", "p": "640", "f": "640"],
                ["n": "Изоляция", "u": "м", "p": "900", "f": "300"]]
    case "tmc":
        return [["n": "Труба нержавеющая AISI 304", "u": "м", "q": "120", "z": "5", "pr": "640"],
                ["n": "Отвод крутоизогнутый 90°", "u": "шт", "q": "30", "z": "5", "pr": "420"]]
    case "rooms":
        return clRoomRows
    case "pipes":
        return [["d": "40", "need": "30,642", "stock": "4", "done": "3,58"],
                ["d": "48", "need": "35,064", "stock": "16", "done": "0"],
                ["d": "57", "need": "91,3", "stock": "64", "done": "17,93"],
                ["d": "76", "need": "63,979", "stock": "15", "done": "15,04"],
                ["d": "89", "need": "39,642", "stock": "18", "done": "31,17"],
                ["d": "108", "need": "9,261", "stock": "13", "done": "21,3"],
                ["d": "133", "need": "23,454", "stock": "12", "done": "14"]]
    default:
        return [["n": "Труба стальная 108х4", "u": "м", "a": "200", "b": "150"]]
    }
}

private let clRoomData: [(String, [(String, String)])] = [
    ("пом. 1079", [("48", "5,684"), ("57", "50,51")]),
    ("пом. 1079", [("40", "9,012"), ("57", "6,942"), ("76", "4,638"), ("89", "11,672")]),
    ("пом. 1100", [("57", "10,2"), ("89", "25,42"), ("108", "0,46"), ("133", "23,454")]),
    ("пом. 1100", [("57", "16,506")]),
    ("пом. 1108", [("48", "16,97"), ("57", "0,666"), ("76", "13,983"), ("89", "2,55"), ("108", "8,801")]),
    ("пом. 1008", [("40", "21,63"), ("76", "8,96")]),
    ("пом. 1008", [("76", "10,35")]),
    ("пом. 1037", [("48", "12,41"), ("76", "10,54")]),
    ("пом. 1029", [("57", "6,476"), ("76", "15,508")])
]

private let clRoomRows: [[String: String]] = clRoomData.flatMap { (room, items) in
    items.map { (d, l) -> [String: String] in ["n": room, "d": d, "l": l] }
}

private func clCellText(_ j: JSON?) -> String {
    guard let j else { return "" }
    if case .n(let v) = j { return clPlain(v, 6) }
    return j.str
}

private func clStoredRows(_ store: Store, _ sheet: ClSheet) -> [[String: String]] {
    guard case .a(let arr)? = store.kv("sh")?[sheet.id] else { return clDefaultRows(sheet.id) }
    return arr.map { item -> [String: String] in
        var d: [String: String] = [:]
        for c in sheet.cols where c.kind != .calc { d[c.k] = clCellText(item[c.k]) }
        return d
    }
}

private func clEncode(_ sheet: ClSheet, _ rows: [ClRow]) -> JSON {
    .a(rows.map { r -> JSON in
        var o: [String: JSON] = [:]
        for c in sheet.cols where c.kind != .calc {
            let s = r.v[c.k] ?? ""
            if c.kind == .num {
                let n = clParse(s)
                o[c.k] = n.isFinite ? .n(n) : .s("")
            } else {
                o[c.k] = .s(s)
            }
        }
        return .o(o)
    })
}

// MARK: - Расчёт

private func clShNum(_ s: String?) -> Double {
    let n = clParse(s ?? "")
    return n.isFinite ? n : 0
}

private func clRowVals(_ sheet: ClSheet, _ v: [String: String], _ p: Double) -> [String: Double] {
    var o: [String: Double] = [:]
    for c in sheet.cols where c.kind == .num { o[c.k] = clShNum(v[c.k]) }
    for c in sheet.cols where c.kind == .calc { o[c.k] = c.f?(o, p) ?? 0 }
    return o
}

private func clTotals(_ sheet: ClSheet, _ rows: [ClRow], _ p: Double) -> [String: Double] {
    var t: [String: Double] = [:]
    let all = rows.map { clRowVals(sheet, $0.v, p) }
    for k in sheet.sums { t[k] = all.reduce(0) { $0 + ($1[k] ?? 0) } }
    for (k, f) in sheet.extraTotals { t[k] = f(t) }
    return t
}

private func clCellString(_ c: ClCol, _ x: Double) -> String {
    switch c.fmt {
    case .pct: return clNum(x * 100, 1) + " %"
    case .status: return x < 0 ? "перерасход" : (x == 0 ? "выбрано" : "в остатке")
    case .int: return clNum(x == 0 ? 0 : x, 0)
    case .dec: return clNum(x == 0 ? 0 : x, 2)
    }
}

/// Сводка по ключу (в вебе svodOf): суммы длин по диаметрам, отсортированные по числу
private func clSvod(_ sheet: ClSheet, _ rows: [[String: String]]) -> [(String, Double)] {
    guard let sv = sheet.svod else { return [] }
    var sums: [String: Double] = [:]
    for r in rows {
        let k = (r[sv.key] ?? "").trimmingCharacters(in: .whitespaces)
        if k.isEmpty { continue }
        sums[k, default: 0] += clShNum(r[sv.val])
    }
    return sums.sorted { a, b in
        let pa = clParse(a.key), pb = clParse(b.key)
        if pa.isFinite && pb.isFinite && pa != pb { return pa < pb }
        return a.key.localizedCompare(b.key) == .orderedAscending
    }.map { ($0.key, $0.value) }
}

// MARK: - Выгрузка CSV

struct ClCSVFile: Transferable {
    let name: String
    let text: String
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .commaSeparatedText) { (file: ClCSVFile) throws -> SentTransferredFile in
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(file.name)
            try Data(("\u{FEFF}" + file.text).utf8).write(to: url, options: .atomic)
            return SentTransferredFile(url)
        }
    }
}

func clCSVEscape(_ s: String) -> String {
    guard s.contains(";") || s.contains("\"") || s.contains("\n") else { return s }
    return "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\""
}

// MARK: - Экран «Расчётные листы»

struct SheetsView: View {
    @EnvironmentObject private var store: Store
    @AppStorage("cl.sheets.tab") private var tabId = "pipes"
    @State private var rows: [ClRow] = []
    @State private var paramText = ""
    @State private var toast: String?
    @State private var showRequests = false
    @State private var saveTask: Task<Void, Never>?
    @FocusState private var focus: String?
    @ScaledMetric(relativeTo: .body) private var rowH: CGFloat = 46
    @ScaledMetric(relativeTo: .caption) private var headH: CGFloat = 62

    private let deleteW: CGFloat = 48

    private var sheet: ClSheet { clSheets.first { $0.id == tabId } ?? clSheets[0] }
    private var param: Double {
        let p = clParse(paramText)
        return p.isFinite && p != 0 ? p : sheet.paramDef
    }
    private var firstW: CGFloat { sheet.cols[0].k == "d" ? 96 : 170 }
    private func width(_ c: ClCol) -> CGFloat { c.kind == .text ? 100 : 135 }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                tabs
                tableCard
                if sheet.svod != nil { svodCard }
            }
            .padding(.horizontal, 16).padding(.bottom, 24)
        }
        .ptoScreen()
        .navigationTitle("Расчётные листы")
        .navigationBarTitleDisplayMode(.inline)
        .scrollDismissesKeyboard(.interactively)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                ShareLink(item: csvFile, preview: SharePreview(sheet.title)) {
                    Label("Выгрузить CSV", systemImage: "square.and.arrow.up")
                }
            }
            ClKeyboardDone { focus = nil }
        }
        .onAppear(perform: load)
        .onDisappear(perform: saveNow)
        .onChange(of: rows) { _ in scheduleSave() }
        .onChange(of: paramText) { _ in scheduleSave() }
        .sheet(isPresented: $showRequests) { ClRequestPicker(onPick: addFromRequest) }
        .clToast($toast)
    }

    // MARK: Вкладки и загрузка

    private var tabs: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(clSheets, id: \.id) { s in
                    Chip(title: s.title, on: s.id == tabId) { switchTab(s.id) }
                }
            }
            .padding(.vertical, 4)
        }
    }

    private func switchTab(_ id: String) {
        saveNow()
        tabId = id
        load()
    }

    private func load() {
        rows = clStoredRows(store, sheet).map { ClRow(v: $0) }
        guard sheet.paramLabel != nil else { paramText = ""; return }
        let stored = store.kv("shp")?[sheet.id]?[clPieceKey].num
        let value = (stored ?? 0) != 0 ? stored! : sheet.paramDef
        paramText = clPlain(value, 3)
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(nanoseconds: 700_000_000)
            if !Task.isCancelled { saveNow() }
        }
    }

    private func saveNow() {
        saveTask?.cancel()
        let sh = sheet
        if rows.map({ $0.v }) != clStoredRows(store, sh) {
            var all = store.kv("sh") ?? .o([:])
            if case .o = all {} else { all = .o([:]) }
            all[sh.id] = clEncode(sh, rows)
            store.setKV("sh", all)
        }
        guard sh.paramLabel != nil else { return }
        let stored = store.kv("shp")?[sh.id]?[clPieceKey].num ?? sh.paramDef
        if stored != param {
            var all = store.kv("shp") ?? .o([:])
            if case .o = all {} else { all = .o([:]) }
            var st = all[sh.id] ?? .o([:])
            if case .o = st {} else { st = .o([:]) }
            st[clPieceKey] = .n(param)
            all[sh.id] = st
            store.setKV("shp", all)
        }
    }

    // MARK: Таблица

    private var tableCard: some View {
        let sh = sheet
        let p = param
        let totals = clTotals(sh, rows, p)
        return VStack(alignment: .leading, spacing: 12) {
            Text(sh.hint).font(.subheadline).foregroundStyle(.secondary)
            if let label = sh.paramLabel { paramField(label) }
            HStack(alignment: .top, spacing: 0) {
                pinnedColumn(sh, totals)
                Divider()
                ScrollView(.horizontal, showsIndicators: true) { scrollingColumns(sh, p, totals) }
            }
            .shPanel(10)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            if rows.isEmpty {
                EmptyNote(title: "Таблица пуста", text: "Нажмите «Добавить строку» или подтяните данные кнопкой ниже")
            }
            Text("Проведите по таблице влево, чтобы увидеть остальные столбцы.")
                .font(.caption).foregroundStyle(.secondary)
            actions
        }
        .padding(14)
        .shPanel(16)
    }

    private func paramField(_ label: String) -> some View {
        HStack {
            Text(label).font(.subheadline)
            Spacer(minLength: 8)
            TextField("\(clNum(sheet.paramDef, 0))", text: $paramText)
                .keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                .font(.body.monospacedDigit()).frame(maxWidth: 110)
                .focused($focus, equals: "param")
        }
        .frame(minHeight: 44)
    }

    private func headerCell(_ c: ClCol, w: CGFloat) -> some View {
        Text(c.label)
            .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            .multilineTextAlignment(c.kind == .text ? .leading : .trailing)
            .frame(width: w - 16, height: headH, alignment: c.kind == .text ? .bottomLeading : .bottomTrailing)
            .padding(.horizontal, 8)
    }

    private func pinnedColumn(_ sh: ClSheet, _ totals: [String: Double]) -> some View {
        let first = sh.cols[0]
        return VStack(spacing: 0) {
            headerCell(first, w: firstW)
            ForEach(rows) { row in
                inputCell(first, row: row, w: firstW).frame(height: rowH).overlay(alignment: .bottom) { Divider() }
            }
            Text("Итого").font(.subheadline.weight(.bold))
                .frame(width: firstW - 16, height: rowH, alignment: .leading).padding(.horizontal, 8)
        }
        .frame(width: firstW)
    }

    private func scrollingColumns(_ sh: ClSheet, _ p: Double, _ totals: [String: Double]) -> some View {
        let others = Array(sh.cols.dropFirst())
        return VStack(spacing: 0) {
            HStack(spacing: 0) {
                ForEach(others, id: \.k) { headerCell($0, w: width($0)) }
                Color.clear.frame(width: deleteW, height: headH)
            }
            ForEach(rows) { row in
                let o = clRowVals(sh, row.v, p)
                HStack(spacing: 0) {
                    ForEach(others, id: \.k) { c in
                        if c.kind == .calc { calcCell(c, o[c.k] ?? 0) } else { inputCell(c, row: row, w: width(c)) }
                    }
                    deleteButton(row)
                }
                .frame(height: rowH)
                .overlay(alignment: .bottom) { Divider() }
            }
            HStack(spacing: 0) {
                ForEach(others, id: \.k) { c in
                    Text(totals[c.k].map { clCellString(c, $0) } ?? "")
                        .font(.subheadline.weight(.bold).monospacedDigit())
                        .frame(width: width(c) - 16, height: rowH, alignment: .trailing).padding(.horizontal, 8)
                }
                Color.clear.frame(width: deleteW, height: rowH)
            }
        }
    }

    private func calcCell(_ c: ClCol, _ x: Double) -> some View {
        let isBad = (c.neg && x < 0) || (c.bad && x > 0)
        let color: Color = isBad ? .red : (c.bad ? .green : .primary)
        return Text(clCellString(c, x))
            .font(.body.monospacedDigit()).foregroundStyle(color)
            .lineLimit(1).minimumScaleFactor(0.7)
            .frame(width: width(c) - 16, alignment: .trailing).padding(.horizontal, 8)
    }

    private func inputCell(_ c: ClCol, row: ClRow, w: CGFloat) -> some View {
        let binding = Binding<String>(
            get: { rows.first { $0.id == row.id }?.v[c.k] ?? "" },
            set: { new in
                if let i = rows.firstIndex(where: { $0.id == row.id }) { rows[i].v[c.k] = new }
            })
        return TextField(c.label, text: binding)
            .keyboardType(c.kind == .num ? .decimalPad : .default)
            .multilineTextAlignment(c.kind == .num ? .trailing : .leading)
            .font(.body.monospacedDigit())
            .focused($focus, equals: "\(row.id.uuidString)-\(c.k)")
            .frame(width: w - 16).padding(.horizontal, 8)
            .accessibilityLabel(c.label)
    }

    private func deleteButton(_ row: ClRow) -> some View {
        Button(role: .destructive) {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { rows.removeAll { $0.id == row.id } }
        } label: {
            Image(systemName: "trash").frame(width: deleteW, height: 44)
        }
        .accessibilityLabel("Удалить строку")
    }

    // MARK: Действия

    private var actions: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(action: addRow) { Label("Добавить строку", systemImage: "plus").frame(maxWidth: .infinity, minHeight: 44) }
                .buttonStyle(.bordered)
            if let label = sheet.importLabel {
                Button(action: runImport) {
                    Label(label, systemImage: "arrow.down.circle").frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private func addRow() {
        var v: [String: String] = [:]
        for c in sheet.cols { if let d = c.def { v[c.k] = d } }
        let row = ClRow(v: v)
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { rows.append(row) }
        focus = "\(row.id.uuidString)-\(sheet.cols[0].k)"
    }

    private func report(_ n: Int) {
        toast = n > 0 ? "Подтянуто строк: \(n)" : "Нечего подтягивать"
    }

    private func upsert(_ key: String, _ value: String, defaults: [String: String]) -> Int {
        let col = sheet.cols[0].k
        if rows.firstIndex(where: { $0.v[col] == value }) == nil { rows.append(ClRow(v: defaults)) }
        return rows.firstIndex(where: { $0.v[col] == value }) ?? 0
    }

    private func runImport() {
        switch sheet.id {
        case "pipes": report(importPipes())
        case "vol": report(importJournal())
        case "mat": report(importMaterials())
        case "tmc": showRequests = true
        default: break
        }
    }

    private func importPipes() -> Int {
        guard let roomsSheet = clSheets.first(where: { $0.id == "rooms" }) else { return 0 }
        let sv = clSvod(roomsSheet, clStoredRows(store, roomsSheet))
        for (d, l) in sv {
            let i = upsert("d", d, defaults: ["d": d, "need": "0", "stock": "0", "done": "0"])
            rows[i].v["need"] = clPlain((l * 1000).rounded() / 1000, 3)
        }
        return sv.count
    }

    private func importJournal() -> Int {
        var by: [String: Double] = [:]
        for j in store.list("journal") {
            let system = j["system"].str
            if system.isEmpty { continue }
            let direct = j["m"].num
            let metres = direct ?? j["lines"].arr.reduce(0) { $0 + ($1["m"].num ?? 0) }
            by[system, default: 0] += metres
        }
        for (s, m) in by.sorted(by: { $0.key < $1.key }) {
            let i = upsert("n", s, defaults: ["n": s, "u": "м", "p": "0", "f": "0"])
            rows[i].v["f"] = clPlain((m * 100).rounded() / 100, 2)
        }
        return by.count
    }

    private func importMaterials() -> Int {
        let mats = store.list("mats")
        for m in mats {
            let name = m["name"].str
            let i = upsert("n", name, defaults: ["n": name, "u": m["unit"].str, "a": "0", "b": "0"])
            rows[i].v["a"] = clPlain(m["rec"].num ?? 0, 6)
            rows[i].v["b"] = clPlain(m["used"].num ?? 0, 6)
        }
        return mats.count
    }

    private func addFromRequest(_ r: Rec) {
        let items = r["items"].arr.filter { !$0["name"].str.trimmingCharacters(in: .whitespaces).isEmpty }
        for i in items {
            let q = clParse(i["qty"].str)
            let v: [String: String] = ["n": i["name"].str, "u": i["unit"].str, "q": clPlain(q.isFinite ? q : 0, 6), "z": "5", "pr": ""]
            rows.append(ClRow(v: v))
        }
        toast = "Добавлено позиций: \(items.count)"
    }

    // MARK: Сводка и CSV

    private var svodCard: some View {
        let sh = sheet
        let sv = clSvod(sh, rows.map { $0.v })
        return Card(title: sh.svod?.label ?? "") {
            if sv.isEmpty {
                Text("Заполните таблицу выше").font(.subheadline).foregroundStyle(.secondary)
            } else {
                Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 8) {
                    GridRow {
                        Text(sh.cols.first { $0.k == sh.svod?.key }?.label ?? "").font(.footnote.weight(.semibold)).foregroundStyle(.secondary)
                        Text(sh.cols.first { $0.k == sh.svod?.val }?.label ?? "").font(.footnote.weight(.semibold)).foregroundStyle(.secondary)
                            .gridColumnAlignment(.trailing)
                    }
                    ForEach(Array(sv.enumerated()), id: \.offset) { _, item in
                        GridRow {
                            Text(item.0)
                            Text(clNum(item.1, 3)).monospacedDigit()
                        }
                    }
                }
            }
        }
    }

    private var csvFile: ClCSVFile {
        let sh = sheet
        let p = param
        var lines: [String] = [clCSVEscape(sh.title)]
        if let label = sh.paramLabel { lines.append(clCSVEscape(label) + ";" + clPlain(p, 3)) }
        lines.append(sh.cols.map { clCSVEscape($0.label) }.joined(separator: ";"))
        for r in rows {
            let o = clRowVals(sh, r.v, p)
            let cells: [String] = sh.cols.map { c in
                c.kind == .calc ? clCSVValue(c, o[c.k] ?? 0) : clCSVEscape(r.v[c.k] ?? "")
            }
            lines.append(cells.joined(separator: ";"))
        }
        let t = clTotals(sh, rows, p)
        let totalCells: [String] = sh.cols.enumerated().map { i, c in
            i == 0 ? "Итого" : (t[c.k].map { clCSVValue(c, $0) } ?? "")
        }
        lines.append(totalCells.joined(separator: ";"))
        let name = "PTO_" + sh.title.replacingOccurrences(of: ":", with: "").replacingOccurrences(of: " ", with: "_") + ".csv"
        return ClCSVFile(name: name, text: lines.joined(separator: "\r\n") + "\r\n")
    }

    private func clCSVValue(_ c: ClCol, _ x: Double) -> String {
        switch c.fmt {
        case .pct: return clPlain(x * 100, 1) + " %"
        case .status: return clCellString(c, x)
        case .int: return clPlain(x, 0)
        case .dec: return clPlain(x, 2)
        }
    }
}

// MARK: - Выбор заявки для сметы ТМЦ

private struct ClRequestPicker: View {
    @EnvironmentObject private var store: Store
    @Environment(\.dismiss) private var dismiss
    let onPick: (Rec) -> Void

    private var requests: [Rec] {
        store.list("requests").sorted { a, b in
            (a["no"].num ?? 0) > (b["no"].num ?? 0)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                if requests.isEmpty {
                    EmptyNote(title: "Заявок пока нет", text: "Создайте заявку в разделе «Заявки на ТМЦ»")
                }
                ForEach(requests) { r in
                    Button {
                        onPick(r)
                        dismiss()
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Заявка №\(r["no"].str) · \(Fmt.show(r["date"].str))").font(.headline)
                            Text("\(r["shop"].str) · \(r["items"].arr.count) поз.").font(.subheadline).foregroundStyle(.secondary)
                        }
                        .frame(minHeight: 44, alignment: .leading)
                    }
                    .tint(.primary)
                }
            }
            .ptoScreen()
            .navigationTitle("Взять из заявки")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
            }
        }
    }
}
