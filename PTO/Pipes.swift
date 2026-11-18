import SwiftUI

// MARK: - Данные сортамента (как в вебе: ROUND_D, INOX_D, INOX_G, PROF_SQ, PROF_RC, PPR)

private enum ClPipeTab: String, CaseIterable {
    case black = "Чёрная сталь", inox = "Нержавеющая", prof = "Профильная", ppr = "PPR (полипропилен)"
}

private let clRoundD: [Double] = [21.3, 26.9, 33.7, 42.4, 48.3, 57, 60.3, 76, 88.9, 89, 108, 114.3, 133, 159, 168.3, 219, 273, 325, 377, 426, 530]
private let clInoxD: [Double] = [12, 14, 16, 18, 20, 22, 25, 28, 32, 38, 40, 42.4, 48.3, 50, 54, 57, 60.3, 63.5, 70, 76.1, 88.9, 101.6, 108, 114.3, 133, 159, 168.3, 219.1, 273, 323.9]
private let clInoxGrades: [(name: String, rho: Double)] = [
    ("AISI 304 (08Х18Н10)", 7.93), ("AISI 316 (10Х17Н13М2)", 7.98), ("AISI 321 (08Х18Н10Т)", 7.9), ("AISI 430 (12Х17)", 7.7)
]
private let clProfSquare: [Double] = [20, 25, 30, 40, 50, 60, 70, 80, 90, 100, 120, 140, 150, 160, 180, 200]
private let clProfRect: [(a: Double, b: Double)] = [
    (30, 15), (40, 20), (50, 25), (50, 30), (60, 30), (60, 40), (80, 40), (80, 60), (100, 50), (100, 60),
    (120, 60), (120, 80), (140, 80), (140, 100), (160, 80), (160, 120), (180, 100), (200, 100), (200, 120), (250, 150)
]
private let clPprSeries: [(name: String, walls: [(d: Double, s: Double)])] = [
    ("PN10 (SDR 11)", [(20, 1.9), (25, 2.3), (32, 2.9), (40, 3.7), (50, 4.6), (63, 5.8), (75, 6.8), (90, 8.2), (110, 10)]),
    ("PN16 (SDR 7,4)", [(20, 2.8), (25, 3.5), (32, 4.4), (40, 5.5), (50, 6.9), (63, 8.6), (75, 10.3), (90, 12.3), (110, 15.1)]),
    ("PN20 (SDR 6)", [(20, 3.4), (25, 4.2), (32, 5.4), (40, 6.7), (50, 8.3), (63, 10.5), (75, 12.5), (90, 15), (110, 18.3)])
]
private let clBlackWalls: [Double] = [2, 2.5, 3, 3.5, 4, 4.5, 5, 6, 7, 8, 9, 10, 12]
private let clInoxWalls: [Double] = [1, 1.5, 2, 2.5, 3, 3.5, 4, 5, 6, 8]
private let clProfWalls: [Double] = [1.5, 2, 2.5, 3, 3.5, 4, 5, 6, 8]

private let clPprDensity = 0.9
private let clProfDensityKgMm2 = 0.00785
private let clMaxWallShare = 0.22
private let clMinBore = 4.0

// MARK: - Формулы

private func clRoundMass(_ d: Double, _ s: Double) -> Double { 0.02466 * (d - s) * s }
private func clInoxMass(_ d: Double, _ s: Double, _ rho: Double) -> Double { Double.pi * rho / 1000 * (d - s) * s }
private func clProfArea(_ a: Double, _ b: Double, _ t: Double) -> Double { 2 * t * (a + b) - (12 - 2 * Double.pi) * t * t }
private func clBoreLitres(_ id: Double) -> Double { Double.pi * id * id / 4 / 1000 }
private func clWalls(_ d: Double, _ list: [Double]) -> [Double] {
    list.filter { d - 2 * $0 > clMinBore && $0 <= d * clMaxWallShare }
}

// MARK: - Таблица со сдвигом по горизонтали

private struct ClGridTable: View {
    let headers: [String]
    let rows: [[String]]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            Grid(alignment: .trailing, horizontalSpacing: 18, verticalSpacing: 10) {
                GridRow {
                    ForEach(headers.indices, id: \.self) { j in
                        Text(headers[j])
                            .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                            .multilineTextAlignment(.trailing)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(minWidth: 62, maxWidth: 96, alignment: .trailing)
                    }
                }
                Divider()
                ForEach(rows.indices, id: \.self) { i in
                    GridRow {
                        ForEach(rows[i].indices, id: \.self) { j in
                            Text(rows[i][j])
                                .font(j == 0 ? .body.weight(.semibold) : .body)
                                .monospacedDigit()
                        }
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }
}

// MARK: - Экран «Сортамент труб»

struct PipesView: View {
    @State private var tab: ClPipeTab = .black
    @State private var diameter: Double = 108
    @State private var gradeIndex = 0
    @State private var square = true
    @State private var profIndex = 3
    @State private var pprIndex = 2
    @State private var lengthText = "100"
    @FocusState private var lengthFocus: Bool

    private var length: Double { max(0, clParse(lengthText).isFinite ? clParse(lengthText) : 0) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                typeChips
                lengthField
                switch tab {
                case .black, .inox: roundBlock
                case .prof: profBlock
                case .ppr: pprBlock
                }
                Text(note).font(.footnote).foregroundStyle(.secondary).padding(.horizontal, 4)
            }
            .padding(.horizontal, 16).padding(.bottom, 24)
            .clColumn()
        }
        .ptoScreen()
        .navigationTitle("Сортамент труб")
        .navigationBarTitleDisplayMode(.inline)
        .scrollDismissesKeyboard(.interactively)
        .toolbar { ClKeyboardDone { lengthFocus = false } }
    }

    // MARK: Общее

    private var typeChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(ClPipeTab.allCases, id: \.self) { t in
                    Chip(title: t.rawValue, on: t == tab) { select(t) }
                }
            }
            .padding(.vertical, 4)
        }
    }

    private func select(_ t: ClPipeTab) {
        tab = t
        if t == .black && !clRoundD.contains(diameter) { diameter = 108 }
        if t == .inox && !clInoxD.contains(diameter) { diameter = 57 }
    }

    private var lengthField: some View {
        HStack {
            Text("Расчёт на длину, м").font(.subheadline).foregroundStyle(.secondary)
            Spacer()
            TextField("100", text: $lengthText)
                .keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                .font(.body.monospacedDigit()).frame(maxWidth: 100)
                .focused($lengthFocus)
        }
        .padding(.horizontal, 14).frame(minHeight: 48)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func chipRow<T: Hashable>(_ items: [T], selected: @escaping (T) -> Bool, title: @escaping (T) -> String, pick: @escaping (T) -> Void) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(items, id: \.self) { item in
                    Chip(title: title(item), on: selected(item)) { pick(item) }
                }
            }
            .padding(.vertical, 4)
        }
    }

    private var note: String {
        switch tab {
        case .black: return "Масса = 0,02466·(D−s)·s, плотность 7850 кг/м³."
        case .inox: return "Масса = π·ρ·(D−s)·s, ρ по марке стали. Наличие типоразмера уточняйте у поставщика (ГОСТ 9941, 11068 и др.)."
        case .prof: return "Сталь 7850 кг/м³, скругление углов: наружный радиус 1,5·t, внутренний 0,5·t. Фактическая масса по ГОСТ 30245 / 8639 / 8645 может отличаться на 1–3 %."
        case .ppr: return "Полипропилен PP-R: плотность 0,9 г/см³. Толщины стенок — типовые по ГОСТ 32415 / DIN 8077; уточняйте у производителя."
        }
    }

    // MARK: Круглые трубы

    private var roundBlock: some View {
        let list = tab == .black ? clRoundD : clInoxD
        let grade = clInoxGrades[gradeIndex]
        let walls = clWalls(diameter, tab == .black ? clBlackWalls : clInoxWalls)
        let rows: [[String]] = walls.map { s in
            let id = diameter - 2 * s
            let m = tab == .black ? clRoundMass(diameter, s) : clInoxMass(diameter, s, grade.rho)
            return [clNum(s, 2), clNum(id, 1), clNum(m, 3), clNum(clBoreLitres(id), 3), clNum(m * length, 1), clNum(Double.pi * diameter / 1000, 3)]
        }
        let heads = ["Стенка, мм", "Внутр. ⌀, мм", "Масса 1 м, кг", "Вода, л/м", "Масса \(clNum(length, 2)) м, кг", "Поверхность, м²/м"]
        let title = "Труба ⌀\(clNum(diameter, 1)) мм" + (tab == .inox ? ", " + grade.name : "")
        return VStack(alignment: .leading, spacing: 14) {
            chipRow(list, selected: { $0 == diameter }, title: { "⌀" + clNum($0, 1) }, pick: { diameter = $0 })
            if tab == .inox {
                Picker("Марка стали", selection: $gradeIndex) {
                    ForEach(clInoxGrades.indices, id: \.self) { Text(clInoxGrades[$0].name).tag($0) }
                }
                .pickerStyle(.menu)
            }
            Card(title: title) {
                if rows.isEmpty { Text("Для этого диаметра нет подходящих стенок").foregroundStyle(.secondary) }
                else { ClGridTable(headers: heads, rows: rows) }
            }
        }
    }

    // MARK: Профильные трубы

    private var profSizes: [(a: Double, b: Double)] { square ? clProfSquare.map { ($0, $0) } : clProfRect }

    private var profBlock: some View {
        let sizes = profSizes
        let idx = min(profIndex, sizes.count - 1)
        let size = sizes[idx]
        let walls = clProfWalls.filter { $0 <= min(size.a, size.b) / 3 }
        let rows: [[String]] = walls.map { t in
            let area = clProfArea(size.a, size.b, t)
            let m = area * clProfDensityKgMm2
            return [clNum(t, 2), clNum(area, 1), clNum(m, 3), clNum(m * length, 1), clNum(2 * (size.a + size.b) / 1000, 3)]
        }
        let heads = ["Стенка, мм", "Сечение, мм²", "Масса 1 м, кг", "Масса \(clNum(length, 2)) м, кг", "Поверхность, м²/м"]
        return VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Chip(title: "Квадратная", on: square) { square = true; profIndex = 3 }
                Chip(title: "Прямоугольная", on: !square) { square = false; profIndex = 1 }
            }
            chipRow(Array(sizes.indices), selected: { $0 == idx }, title: { "\(clNum(sizes[$0].a, 0))×\(clNum(sizes[$0].b, 0))" }, pick: { profIndex = $0 })
            Card(title: "Профильная труба \(clNum(size.a, 0))×\(clNum(size.b, 0)) мм") {
                ClGridTable(headers: heads, rows: rows)
            }
        }
    }

    // MARK: PPR

    private var pprBlock: some View {
        let series = clPprSeries[pprIndex]
        let rows: [[String]] = series.walls.map { w in
            let id = w.d - 2 * w.s
            let m = Double.pi / 4 * (w.d * w.d - id * id) * clPprDensity / 1000
            return [clNum(w.d, 0), clNum(w.s, 1), clNum(id, 1), clNum(clBoreLitres(id), 3), clNum(m, 3), clNum(m * length, 1)]
        }
        let heads = ["Наружный ⌀, мм", "Стенка, мм", "Внутр. ⌀, мм", "Вода, л/м", "Масса 1 м, кг", "Масса \(clNum(length, 2)) м, кг"]
        return VStack(alignment: .leading, spacing: 14) {
            chipRow(Array(clPprSeries.indices), selected: { $0 == pprIndex }, title: { clPprSeries[$0].name }, pick: { pprIndex = $0 })
            Card(title: "Труба PPR, \(series.name)") { ClGridTable(headers: heads, rows: rows) }
        }
    }
}
