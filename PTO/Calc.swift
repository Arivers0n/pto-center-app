import SwiftUI

// MARK: - Общие помощники группы «Расчёты и справочники» (префикс Cl)

/// Число как в вебе (`nf`): по-русски, «—» если не число
func clNum(_ v: Double, _ digits: Int = 2) -> String { v.isFinite ? Fmt.num(v, digits) : "—" }

/// Число без пробелов-разделителей: его удобно вставлять в Excel
func clPlain(_ v: Double, _ digits: Int = 3) -> String {
    guard v.isFinite else { return "" }
    return Fmt.num(v, digits).filter { !$0.isWhitespace }
}

/// Разбор введённого числа: запятая или точка, пусто — не число
func clParse(_ s: String) -> Double {
    let t = s.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespaces)
    return Double(t) ?? .nan
}

func clCopy(_ text: String) {
    UIPasteboard.general.string = text
    UINotificationFeedbackGenerator().notificationOccurred(.success)
}

extension View {
    /// Колонка до 720 pt по центру (iPad)
    func clColumn() -> some View { self.frame(maxWidth: 720).frame(maxWidth: .infinity) }
    func clToast(_ text: Binding<String?>) -> some View { modifier(ClToastModifier(text: text)) }
}

struct ClToastModifier: ViewModifier {
    @Binding var text: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func body(content: Content) -> some View {
        let shift: AnyTransition = reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity)
        content
            .overlay(alignment: .bottom) {
                if let t = text {
                    Text(t)
                        .font(.subheadline.weight(.medium))
                        .padding(.horizontal, 16).padding(.vertical, 10)
                        .background(.ultraThinMaterial, in: Capsule())
                        .padding(.bottom, 24)
                        .transition(shift)
                        .task(id: t) {
                            try? await Task.sleep(nanoseconds: 1_600_000_000)
                            withAnimation { text = nil }
                        }
                        .accessibilityAddTraits(.updatesFrequently)
                }
            }
            .animation(.spring(response: 0.35, dampingFraction: 0.85), value: text)
    }
}

/// Кнопка «Готово» над клавиатурой
struct ClKeyboardDone: ToolbarContent {
    let action: () -> Void
    var body: some ToolbarContent {
        ToolbarItemGroup(placement: .keyboard) {
            Spacer()
            Button("Готово", action: action)
        }
    }
}

// MARK: - Данные калькуляторов (как CALCS в вебе)

private struct ClVals {
    let d: [String: Double]
    subscript(_ k: String) -> Double { d[k] ?? .nan }
}

private struct ClField { let k: String; let label: String; let unit: String; let def: String }
private struct ClOut { let label: String; let unit: String; let digits: Int; let f: (ClVals) -> Double }
private struct ClCalc { let name: String; let fields: [ClField]; let outs: [ClOut]; var inchTable = false }

private let clDN: [Double: Int] = [0.5: 15, 0.75: 20, 1: 25, 1.25: 32, 1.5: 40, 2: 50, 2.5: 65, 3: 80, 4: 100, 5: 125, 6: 150, 8: 200, 10: 250, 12: 300]
private let clDNOrder: [Double] = [0.5, 0.75, 1, 1.25, 1.5, 2, 2.5, 3, 4, 5, 6, 8, 10, 12]
private let clDNOuter: [Int: Double] = [15: 21.3, 20: 26.9, 25: 33.7, 32: 42.4, 40: 48.3, 50: 60.3, 65: 76.1, 80: 88.9, 100: 114.3, 125: 139.7, 150: 168.3, 200: 219.1, 250: 273, 300: 323.9]

private let clSteelKgPerMm = 0.02466
private let clKgfPerMPa = 10.1972

private func clDNValue(_ inch: Double) -> Double {
    guard let dn = clDN[inch] else { return .nan }
    return Double(dn)
}
private func clDNOuterValue(_ inch: Double) -> Double {
    guard let dn = clDN[inch], let od = clDNOuter[dn] else { return .nan }
    return od
}
private func clPipeMass(_ x: ClVals) -> Double { clSteelKgPerMm * (x["D"] - x["s"]) * x["s"] }
private func clWaterM3(_ x: ClVals) -> Double {
    let d = (x["D"] - 2 * x["s"]) / 1000
    return Double.pi * d * d / 4 * x["L"]
}
private func clConcrete(_ x: ClVals) -> Double { x["a"] * x["b"] * x["h"] * x["n"] }
private func clPit(_ x: ClVals) -> Double {
    let h = x["h"], m = x["m"]
    let base = x["a"] * x["b"] + (x["a"] + x["b"]) * m * h
    return h * (base + 4 / 3 * m * m * h * h)
}
private func clRebar1m(_ x: ClVals) -> Double { x["d"] * x["d"] / 162 }

private let clCalcs: [ClCalc] = [
    ClCalc(name: "Вес трубы",
           fields: [ClField(k: "D", label: "Наружный диаметр", unit: "мм", def: "108"),
                    ClField(k: "s", label: "Стенка", unit: "мм", def: "4"),
                    ClField(k: "L", label: "Длина", unit: "м", def: "100")],
           outs: [ClOut(label: "Масса 1 м", unit: "кг/м", digits: 3) { clPipeMass($0) },
                  ClOut(label: "Масса трубы", unit: "кг", digits: 3) { clPipeMass($0) * $0["L"] },
                  ClOut(label: "Масса трубы", unit: "т", digits: 3) { clPipeMass($0) * $0["L"] / 1000 }]),
    ClCalc(name: "Объём воды",
           fields: [ClField(k: "D", label: "Наружный диаметр", unit: "мм", def: "108"),
                    ClField(k: "s", label: "Стенка", unit: "мм", def: "4"),
                    ClField(k: "L", label: "Длина", unit: "м", def: "100")],
           outs: [ClOut(label: "Внутренний диаметр", unit: "мм", digits: 3) { $0["D"] - 2 * $0["s"] },
                  ClOut(label: "Объём воды", unit: "м³", digits: 3) { clWaterM3($0) },
                  ClOut(label: "Объём воды", unit: "л", digits: 3) { clWaterM3($0) * 1000 }]),
    ClCalc(name: "Давление",
           fields: [ClField(k: "p", label: "Рабочее давление", unit: "МПа", def: "0,4"),
                    ClField(k: "k", label: "Коэффициент (по проекту / СП)", unit: "", def: "1,5")],
           outs: [ClOut(label: "Испытательное", unit: "МПа", digits: 3) { $0["p"] * $0["k"] },
                  ClOut(label: "Испытательное", unit: "кгс/см²", digits: 3) { $0["p"] * $0["k"] * clKgfPerMPa },
                  ClOut(label: "Рабочее", unit: "кгс/см²", digits: 3) { $0["p"] * clKgfPerMPa }]),
    ClCalc(name: "Бетон",
           fields: [ClField(k: "a", label: "Длина", unit: "м", def: "10"),
                    ClField(k: "b", label: "Ширина", unit: "м", def: "8"),
                    ClField(k: "h", label: "Высота / толщина", unit: "м", def: "0,8"),
                    ClField(k: "n", label: "Количество", unit: "шт", def: "1"),
                    ClField(k: "z", label: "Запас", unit: "%", def: "3"),
                    ClField(k: "r", label: "Армирование", unit: "кг/м³", def: "100")],
           outs: [ClOut(label: "Объём бетона", unit: "м³", digits: 3) { clConcrete($0) },
                  ClOut(label: "К заказу с запасом", unit: "м³", digits: 3) { clConcrete($0) * (1 + $0["z"] / 100) },
                  ClOut(label: "Масса арматуры", unit: "т", digits: 3) { clConcrete($0) * $0["r"] / 1000 }]),
    ClCalc(name: "Котлован",
           fields: [ClField(k: "a", label: "Длина по дну", unit: "м", def: "20"),
                    ClField(k: "b", label: "Ширина по дну", unit: "м", def: "12"),
                    ClField(k: "h", label: "Глубина", unit: "м", def: "3,5"),
                    ClField(k: "m", label: "Заложение откоса m", unit: "", def: "0,5"),
                    ClField(k: "kr", label: "Коэфф. разрыхления Kр", unit: "", def: "1,2")],
           outs: [ClOut(label: "Объём выемки", unit: "м³", digits: 3) { clPit($0) },
                  ClOut(label: "Объём вывоза", unit: "м³", digits: 3) { $0["kr"] * clPit($0) },
                  ClOut(label: "Площадь по верху", unit: "м²", digits: 3) {
                      (($0["a"] + 2 * $0["m"] * $0["h"]) * ($0["b"] + 2 * $0["m"] * $0["h"]))
                  }]),
    ClCalc(name: "Арматура",
           fields: [ClField(k: "d", label: "Диаметр", unit: "мм", def: "16"),
                    ClField(k: "l", label: "Длина 1 шт.", unit: "м", def: "11,7"),
                    ClField(k: "n", label: "Количество", unit: "шт", def: "120")],
           outs: [ClOut(label: "Масса 1 м", unit: "кг", digits: 3) { clRebar1m($0) },
                  ClOut(label: "Общая масса", unit: "кг", digits: 3) { clRebar1m($0) * $0["l"] * $0["n"] },
                  ClOut(label: "Общая масса", unit: "т", digits: 3) { clRebar1m($0) * $0["l"] * $0["n"] / 1000 }]),
    ClCalc(name: "Изоляция",
           fields: [ClField(k: "L", label: "Длина трубопровода", unit: "м", def: "100"),
                    ClField(k: "z", label: "Запас на подрезку", unit: "%", def: "5")],
           outs: [ClOut(label: "К заказу", unit: "м.п.", digits: 3) { $0["L"] * (1 + $0["z"] / 100) }]),
    ClCalc(name: "Дюйм → DN",
           fields: [ClField(k: "i", label: "Дюймы", unit: "″", def: "2")],
           outs: [ClOut(label: "DN", unit: "мм", digits: 3) { clDNValue($0["i"]) },
                  ClOut(label: "Наружный Ø (сталь)", unit: "мм", digits: 3) { clDNOuterValue($0["i"]) }],
           inchTable: true)
]

// MARK: - Экран «Калькуляторы»

struct CalcView: View {
    @AppStorage("cl.calc.tab") private var tabName = "Вес трубы"
    @AppStorage("cl.calc.vals") private var rawVals = ""
    @State private var vals: [String: String] = [:]
    @State private var toast: String?
    @FocusState private var focus: String?

    private var calc: ClCalc { clCalcs.first { $0.name == tabName } ?? clCalcs[0] }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                tabs
                inputCard
                resultCard
                if calc.inchTable { inchCard }
            }
            .padding(.horizontal, 16).padding(.bottom, 24)
            .clColumn()
        }
        .ptoScreen()
        .navigationTitle("Калькуляторы")
        .navigationBarTitleDisplayMode(.inline)
        .scrollDismissesKeyboard(.interactively)
        .toolbar { ClKeyboardDone { focus = nil } }
        .onAppear(perform: loadVals)
        .clToast($toast)
    }

    private var tabs: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(clCalcs, id: \.name) { c in
                    Chip(title: c.name, on: c.name == tabName) { tabName = c.name }
                }
            }
            .padding(.vertical, 4)
        }
    }

    private var inputCard: some View {
        Card(title: calc.name) {
            VStack(spacing: 0) {
                ForEach(calc.fields, id: \.k) { f in
                    fieldRow(f)
                    if f.k != calc.fields.last?.k { Divider() }
                }
            }
        }
    }

    private func fieldRow(_ f: ClField) -> some View {
        let key = tabName + "." + f.k
        let binding = Binding<String>(
            get: { vals[key] ?? f.def },
            set: { vals[key] = $0; saveVals() }
        )
        return HStack(spacing: 8) {
            Text(f.label).font(.subheadline).foregroundStyle(.secondary)
            Spacer(minLength: 8)
            TextField("0", text: binding)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .font(.body.monospacedDigit())
                .frame(maxWidth: 120)
                .focused($focus, equals: key)
            if !f.unit.isEmpty {
                Text(f.unit).font(.subheadline).foregroundStyle(.secondary).frame(minWidth: 36, alignment: .leading)
            }
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        .onTapGesture { focus = key }
        .accessibilityElement(children: .combine)
    }

    private var currentValues: ClVals {
        var d: [String: Double] = [:]
        for f in calc.fields { d[f.k] = clParse(vals[tabName + "." + f.k] ?? f.def) }
        return ClVals(d: d)
    }

    private var resultCard: some View {
        let x = currentValues
        let lines: [(ClOut, Double)] = calc.outs.map { ($0, $0.f(x)) }
        return Card(title: "Результат") {
            VStack(spacing: 0) {
                ForEach(Array(lines.enumerated()), id: \.offset) { i, pair in
                    resultRow(pair.0, pair.1)
                    if i < lines.count - 1 { Divider() }
                }
            }
            Button {
                let text = lines.map { "\($0.0.label): \(clPlain($0.1, $0.0.digits)) \($0.0.unit)" }.joined(separator: "\n")
                clCopy(text)
                toast = "Результаты скопированы"
            } label: {
                Label("Скопировать всё", systemImage: "doc.on.doc").frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.bordered)
        }
    }

    private func resultRow(_ o: ClOut, _ v: Double) -> some View {
        Button {
            clCopy(clPlain(v, o.digits))
            toast = "Скопировано: \(clNum(v, o.digits)) \(o.unit)"
        } label: {
            HStack {
                Text(o.label).font(.subheadline).foregroundStyle(.secondary)
                Spacer()
                Text("\(clNum(v, o.digits)) \(o.unit)").font(.headline.monospacedDigit()).foregroundStyle(.primary)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("Скопировать значение")
    }

    private var inchCard: some View {
        Card(title: "Дюйм и DN") {
            Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 8) {
                GridRow {
                    Text("Дюйм").font(.footnote.weight(.semibold)).foregroundStyle(.secondary)
                    Text("DN").font(.footnote.weight(.semibold)).foregroundStyle(.secondary)
                }
                ForEach(clDNOrder, id: \.self) { a in
                    GridRow {
                        Text("\(clNum(a, 2))″").monospacedDigit()
                        Text("\(clDN[a] ?? 0)").monospacedDigit()
                    }
                }
            }
        }
    }

    private func loadVals() {
        guard vals.isEmpty, let data = rawVals.data(using: .utf8),
              let m = try? JSONDecoder().decode([String: String].self, from: data) else { return }
        vals = m
    }

    private func saveVals() {
        guard let data = try? JSONEncoder().encode(vals), let s = String(data: data, encoding: .utf8) else { return }
        rawVals = s
    }
}
