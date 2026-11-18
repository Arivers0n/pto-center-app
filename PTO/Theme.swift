import SwiftUI

// Тема оформления: палитры и стеклянные темы из веб-версии (v7, v15, glass.css).
// Хранится на устройстве (UserDefaults), на сервер не отправляется.
// Подпись ptoScreen() менять нельзя: её вызывает каждый экран.

extension Color {
    init(shHex: UInt32, alpha: Double = 1) {
        self.init(.sRGB,
                  red: Double((shHex >> 16) & 0xFF) / 255,
                  green: Double((shHex >> 8) & 0xFF) / 255,
                  blue: Double(shHex & 0xFF) / 255,
                  opacity: alpha)
    }
}

// MARK: - Описание тем

/// Цветное пятно под стеклом: центр в долях экрана, радиус в пунктах
struct ShSpot {
    let hex: UInt32
    let alpha: Double
    let x: CGFloat
    let y: CGFloat
    let radius: CGFloat
}

struct ShGlassSpec {
    let tint: UInt32          // цвет панели
    let tintAlpha: Double
    let border: UInt32
    let borderAlpha: Double
    let spots: [ShSpot]
    let grid: Bool
}

struct ShSkinSpec {
    let title: String
    let detail: String
    let scheme: ColorScheme?   // nil: следует настройке «Вид»
    let bg: UInt32
    let panel: UInt32
    let text: UInt32
    let accent: UInt32
    var glass: ShGlassSpec? = nil
    var grid: Bool = false     // сетка чертежа на сплошной теме
    var maxRadius: CGFloat = 100
    var outline: Bool = false  // тёмная рамка вместо тени («Чертёж»)
}

enum ShSkin: String, CaseIterable, Identifiable {
    case standard, night, blueprint, draft, table, gNight, gFrost, gBlue, gConcrete, gDusk, gMint
    var id: String { rawValue }
    var isGlass: Bool { spec.glass != nil }

    var spec: ShSkinSpec {
        switch self {
        case .standard:
            return ShSkinSpec(title: "Обычная", detail: "Тёмная или светлая — как выбрано выше", scheme: nil,
                              bg: 0x0b0c0f, panel: 0x15171b, text: 0xeceef2, accent: 0x8ea2ff)
        case .night:
            return ShSkinSpec(title: "Ночная смена", detail: "Сине-графитовая, янтарный сигнал", scheme: .dark,
                              bg: 0x121821, panel: 0x1e2633, text: 0xe8ecf3, accent: 0xf2b23a)
        case .blueprint:
            return ShSkinSpec(title: "Синька", detail: "Светокопия чертежа с сеткой", scheme: .dark,
                              bg: 0x0b2140, panel: 0x133156, text: 0xedf4ff, accent: 0xffd166, grid: true, maxRadius: 8)
        case .draft:
            return ShSkinSpec(title: "Чертёж", detail: "Бумага, тушь, чёткие линии", scheme: .light,
                              bg: 0xf4f1e9, panel: 0xfffdf8, text: 0x16233b, accent: 0x16233b, maxRadius: 5, outline: true)
        case .table:
            return ShSkinSpec(title: "Таблица", detail: "Плотные строки, как в Excel", scheme: .light,
                              bg: 0xeef1f0, panel: 0xffffff, text: 0x122019, accent: 0x0f6b4f, maxRadius: 12)
        case .gNight:
            return ShSkinSpec(title: "Ночная смена · стекло", detail: "Прожекторы сквозь матовое стекло", scheme: .dark,
                              bg: 0x0c1320, panel: 0x1e2a3e, text: 0xeef2f8, accent: 0xffb547,
                              glass: ShGlassSpec(tint: 0x121a28, tintAlpha: 0.46, border: 0xffffff, borderAlpha: 0.09, spots: [
                                ShSpot(hex: 0xffa032, alpha: 0.38, x: 0.18, y: 0.08, radius: 620),
                                ShSpot(hex: 0x3c8cff, alpha: 0.36, x: 0.92, y: 0.18, radius: 640),
                                ShSpot(hex: 0x1ec8b4, alpha: 0.22, x: 0.55, y: 0.95, radius: 560)], grid: false))
        case .gFrost:
            return ShSkinSpec(title: "Утро на стройке", detail: "Светлое матовое стекло, оранжевый каски", scheme: .light,
                              bg: 0xe6eef8, panel: 0xffffff, text: 0x14202f, accent: 0xf0640f,
                              glass: ShGlassSpec(tint: 0xffffff, tintAlpha: 0.58, border: 0xffffff, borderAlpha: 0.75, spots: [
                                ShSpot(hex: 0xffa65c, alpha: 0.34, x: 0.85, y: -0.05, radius: 600),
                                ShSpot(hex: 0x78afff, alpha: 0.40, x: -0.05, y: 0.30, radius: 640)], grid: false))
        case .gBlue:
            return ShSkinSpec(title: "Синька под стеклом", detail: "Сетка чертежа сквозь панели", scheme: .dark,
                              bg: 0x0b2446, panel: 0x1b385b, text: 0xeef5ff, accent: 0x7fe0ff,
                              glass: ShGlassSpec(tint: 0x123058, tintAlpha: 0.5, border: 0xa0cdff, borderAlpha: 0.2, spots: [
                                ShSpot(hex: 0x174a86, alpha: 1, x: 0.8, y: 0, radius: 700)], grid: true))
        case .gConcrete:
            return ShSkinSpec(title: "Бетон и каска", detail: "Тёплый графит, сигнальный жёлтый", scheme: .dark,
                              bg: 0x1a1917, panel: 0x2a2825, text: 0xf3efe8, accent: 0xf5c400,
                              glass: ShGlassSpec(tint: 0x282521, tintAlpha: 0.55, border: 0xfff5e1, borderAlpha: 0.09, spots: [
                                ShSpot(hex: 0xf5c400, alpha: 0.10, x: 0, y: 0, radius: 620),
                                ShSpot(hex: 0xff8c3c, alpha: 0.08, x: 1, y: 1, radius: 700)], grid: false))
        case .gDusk:
            return ShSkinSpec(title: "Сумерки", detail: "Фиолетово-бирюзовое стекло", scheme: .dark,
                              bg: 0x140f24, panel: 0x2a2046, text: 0xf1edfb, accent: 0x5ee6c8,
                              glass: ShGlassSpec(tint: 0x221a3c, tintAlpha: 0.5, border: 0xdcd2ff, borderAlpha: 0.12, spots: [
                                ShSpot(hex: 0x965aff, alpha: 0.38, x: 0.10, y: 0, radius: 620),
                                ShSpot(hex: 0x28c8b4, alpha: 0.26, x: 1, y: 0.30, radius: 660),
                                ShSpot(hex: 0xff78aa, alpha: 0.16, x: 0.5, y: 1.05, radius: 520)], grid: false))
        case .gMint:
            return ShSkinSpec(title: "Мята", detail: "Светлое стекло, зелёный акцент", scheme: .light,
                              bg: 0xe9f5f0, panel: 0xffffff, text: 0x10241c, accent: 0x0f8a62,
                              glass: ShGlassSpec(tint: 0xffffff, tintAlpha: 0.6, border: 0xffffff, borderAlpha: 0.8, spots: [
                                ShSpot(hex: 0x78dcb4, alpha: 0.42, x: 0.9, y: -0.05, radius: 600),
                                ShSpot(hex: 0x96d2ff, alpha: 0.32, x: -0.05, y: 0.40, radius: 640)], grid: false))
        }
    }
}

/// Акцентный цвет: «По теме» берёт цвет самой темы
enum ShAccent: String, CaseIterable, Identifiable {
    case skin, teal, green, amber, rose, steel
    var id: String { rawValue }
    var title: String {
        switch self {
        case .skin: return "По теме"
        case .teal: return "Бирюза"
        case .green: return "Зелёный"
        case .amber: return "Янтарь"
        case .rose: return "Коралл"
        case .steel: return "Сталь"
        }
    }
    /// (тёмная тема, светлая тема)
    var hex: (dark: UInt32, light: UInt32) {
        switch self {
        case .skin: return (0x8ea2ff, 0x3a50d0)
        case .teal: return (0x4fd1c5, 0x0b7268)
        case .green: return (0x5fd38d, 0x1b7a43)
        case .amber: return (0xf5b84a, 0x8a5a00)
        case .rose: return (0xff8fa3, 0xb4284a)
        case .steel: return (0x9fb3c8, 0x3d566e)
        }
    }
}

enum ShAppearance: String, CaseIterable, Identifiable {
    case auto, dark, light
    var id: String { rawValue }
    var title: String {
        switch self {
        case .auto: return "Как в системе"
        case .dark: return "Тёмная"
        case .light: return "Светлая"
        }
    }
}

// MARK: - Хранилище настроек оформления

final class ThemeStore: ObservableObject {
    @Published var skin: ShSkin { didSet { defaults.set(skin.rawValue, forKey: "pto.skin") } }
    @Published var accent: ShAccent { didSet { defaults.set(accent.rawValue, forKey: "pto.accent") } }
    @Published var appearance: ShAppearance { didSet { defaults.set(appearance.rawValue, forKey: "pto.appearance") } }
    @Published var compact: Bool { didSet { defaults.set(compact, forKey: "pto.compact") } }
    @Published var solid: Bool { didSet { defaults.set(solid, forKey: "pto.solid") } }
    @Published var hidden: [String] { didSet { defaults.set(hidden, forKey: "pto.hidden") } }

    private let defaults = UserDefaults.standard

    init() {
        let d = UserDefaults.standard
        skin = ShSkin(rawValue: d.string(forKey: "pto.skin") ?? "") ?? .standard
        accent = ShAccent(rawValue: d.string(forKey: "pto.accent") ?? "") ?? .skin
        appearance = ShAppearance(rawValue: d.string(forKey: "pto.appearance") ?? "") ?? .auto
        compact = d.bool(forKey: "pto.compact")
        solid = d.bool(forKey: "pto.solid")
        hidden = d.stringArray(forKey: "pto.hidden") ?? []
    }

    /// Схема, которую просим у системы: у тем со своим фоном она задана, у «Обычной» — по выбору
    var preferredScheme: ColorScheme? {
        if let s = skin.spec.scheme { return s }
        switch appearance {
        case .auto: return nil
        case .dark: return .dark
        case .light: return .light
        }
    }

    func effective(_ system: ColorScheme) -> ColorScheme { preferredScheme ?? system }

    func tintHex(_ system: ColorScheme) -> UInt32 {
        let dark = effective(system) == .dark
        if accent != .skin { return dark ? accent.hex.dark : accent.hex.light }
        if skin == .standard { return dark ? ShAccent.skin.hex.dark : ShAccent.skin.hex.light }
        return skin.spec.accent
    }

    func tint(_ system: ColorScheme) -> Color { Color(shHex: tintHex(system)) }

    /// Цвет текста на акцентной заливке: тёмный на светлом акценте и наоборот
    func onTint(_ system: ColorScheme) -> Color {
        let h = tintHex(system)
        let r = Double((h >> 16) & 0xFF), g = Double((h >> 8) & 0xFF), b = Double(h & 0xFF)
        let luma = (0.299 * r + 0.587 * g + 0.114 * b) / 255
        return luma > 0.62 ? Color(shHex: 0x14171c) : Color.white
    }

    func base() -> Color {
        skin == .standard ? Color(.systemGroupedBackground) : Color(shHex: skin.spec.bg)
    }

    func panel() -> Color {
        skin == .standard ? Color(.secondarySystemGroupedBackground) : Color(shHex: skin.spec.panel)
    }

    func control() -> Color {
        skin == .standard ? Color(.tertiarySystemGroupedBackground) : Color(shHex: skin.spec.bg).opacity(0.55)
    }

    /// Пункт меню виден, если не скрыт в настройках (главная и настройки скрыть нельзя)
    func isVisible(_ s: ShSection, keep: ShSection? = nil) -> Bool {
        s == .home || s == .settings || s == keep || !hidden.contains(s.rawValue)
    }

    func setHidden(_ s: ShSection, _ hide: Bool) {
        var h = hidden.filter { $0 != s.rawValue }
        if hide { h.append(s.rawValue) }
        hidden = h
    }
}

// MARK: - Фон

private struct ShSpotView: View {
    let spot: ShSpot
    var body: some View {
        let c = Color(shHex: spot.hex, alpha: spot.alpha)
        RadialGradient(colors: [c, c.opacity(0)],
                       center: UnitPoint(x: spot.x, y: spot.y), startRadius: 0, endRadius: spot.radius)
    }
}

private struct ShSpots: View {
    let spots: [ShSpot]
    var body: some View {
        ZStack {
            ForEach(Array(spots.enumerated()), id: \.offset) { _, s in
                ShSpotView(spot: s)
            }
        }
    }
}

/// Сетка чертежа: мелкая через 24 пункта, крупная через 120
private struct ShGridLines: View {
    let hex: UInt32
    let minorAlpha: Double
    let majorAlpha: Double
    var body: some View {
        Canvas { ctx, size in
            let layers: [(CGFloat, Double)] = [(24, minorAlpha), (120, majorAlpha)]
            for (step, alpha) in layers {
                var p = Path()
                var x: CGFloat = 0
                while x <= size.width {
                    p.move(to: CGPoint(x: x, y: 0))
                    p.addLine(to: CGPoint(x: x, y: size.height))
                    x += step
                }
                var y: CGFloat = 0
                while y <= size.height {
                    p.move(to: CGPoint(x: 0, y: y))
                    p.addLine(to: CGPoint(x: size.width, y: y))
                    y += step
                }
                ctx.stroke(p, with: .color(Color(shHex: hex, alpha: alpha)), lineWidth: 0.5)
            }
        }
        .allowsHitTesting(false)
    }
}

/// Слои фона темы: используется и на экранах, и в плитках предпросмотра
struct ShBackdrop: View {
    let skin: ShSkin
    let base: Color
    var body: some View {
        ZStack {
            base
            if let g = skin.spec.glass {
                ShSpots(spots: g.spots)
                if g.grid { ShGridLines(hex: 0x96c8ff, minorAlpha: 0.045, majorAlpha: 0.085) }
            } else if skin.spec.grid {
                ShGridLines(hex: 0xffffff, minorAlpha: 0.035, majorAlpha: 0.05)
            }
        }
    }
}

struct ShBackground: View {
    @EnvironmentObject var theme: ThemeStore
    var body: some View {
        ShBackdrop(skin: theme.skin, base: theme.base()).ignoresSafeArea()
    }
}

// MARK: - Панели

/// Заливка панели: стекло (материал + тонировка) или сплошной цвет темы
struct ShPanelFill<S: InsettableShape>: View {
    let shape: S
    @EnvironmentObject var theme: ThemeStore
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        if let g = theme.skin.spec.glass, !theme.solid, !reduceTransparency {
            ZStack {
                shape.fill(.ultraThinMaterial)
                shape.fill(Color(shHex: g.tint, alpha: g.tintAlpha))
            }
            .overlay(shape.strokeBorder(Color(shHex: g.border, alpha: g.borderAlpha), lineWidth: 1))
        } else if theme.skin.spec.outline {
            shape.fill(theme.panel())
                .overlay(shape.strokeBorder(Color(shHex: theme.skin.spec.text), lineWidth: 1.5))
        } else {
            shape.fill(theme.panel())
        }
    }
}

private struct ShPanelModifier: ViewModifier {
    let radius: CGFloat
    @EnvironmentObject var theme: ThemeStore
    func body(content: Content) -> some View {
        let r = min(radius, theme.skin.spec.maxRadius)
        content.background(ShPanelFill(shape: RoundedRectangle(cornerRadius: r, style: .continuous)))
    }
}

extension View {
    /// Панель в цвете темы (карточки, плитки)
    func shPanel(_ radius: CGFloat = 16) -> some View { modifier(ShPanelModifier(radius: radius)) }
}

// MARK: - Экран

private struct ShScreen: ViewModifier {
    @EnvironmentObject var theme: ThemeStore
    @Environment(\.colorScheme) private var scheme
    func body(content: Content) -> some View {
        content
            .scrollContentBackground(.hidden)
            .background(ShBackground())
            .tint(theme.tint(scheme))
            .preferredColorScheme(theme.preferredScheme)
            .environment(\.defaultMinListRowHeight, theme.compact ? 34 : 44)
    }
}

extension View {
    /// Фон экрана и прозрачные списки в выбранной теме. Вызывать на корне содержимого каждого экрана.
    func ptoScreen() -> some View { modifier(ShScreen()) }
}
