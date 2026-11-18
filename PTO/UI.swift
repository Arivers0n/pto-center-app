import SwiftUI

// Общие элементы интерфейса. Имена и подписи менять нельзя: ими пользуются все экраны.
// Все элементы подхватывают тему из ThemeStore.

struct Tile: View {
    let value: String, label: String, icon: String
    var tint: Color = .pto
    let tap: () -> Void
    @EnvironmentObject private var theme: ThemeStore
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let color = tint == .pto ? theme.tint(scheme) : tint
        let big = typeSize.isAccessibilitySize
        Button(action: tap) {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: icon).font(.title3).foregroundStyle(color)
                Text(value).font(.title2.bold()).monospacedDigit().foregroundStyle(.primary)
                    .lineLimit(1).minimumScaleFactor(0.6)
                Text(label).font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.leading)
                    .lineLimit(big ? 6 : 2, reservesSpace: !big)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(theme.compact ? 10 : 14)
            .shPanel(16)
        }
        .buttonStyle(Pressable())
    }
}

struct Card<C: View>: View {
    let title: String
    @ViewBuilder let content: () -> C
    @EnvironmentObject private var theme: ThemeStore
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.headline)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(theme.compact ? 10 : 14)
        .shPanel(16)
    }
}

/// Нажатие ощущается: карточка слегка сжимается и пружинит обратно (без движения при «Уменьшении движения»)
struct Pressable: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        ShPressBody(configuration: configuration)
    }
}

private struct ShPressBody: View {
    let configuration: ButtonStyleConfiguration
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        let shrink = configuration.isPressed && !reduceMotion
        configuration.label
            .scaleEffect(shrink ? 0.97 : 1)
            .opacity(configuration.isPressed && reduceMotion ? 0.7 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

struct Chip: View {
    let title: String
    var count: Int? = nil
    let on: Bool
    let tap: () -> Void
    @EnvironmentObject private var theme: ThemeStore
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let ink = theme.onTint(scheme)
        Button(action: { withAnimation(.easeOut(duration: 0.2)) { tap() } }) {
            HStack(spacing: 5) {
                Text(title)
                if let count {
                    Text("\(count)").foregroundStyle(on ? ink.opacity(0.8) : Color.secondary).monospacedDigit()
                }
            }
            .font(.subheadline.weight(on ? .semibold : .regular))
            .padding(.horizontal, 12).padding(.vertical, 7)
            .frame(minHeight: 36)
            .background(chipFill)
            .foregroundStyle(on ? ink : Color.primary)
        }
        .buttonStyle(Pressable())
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    @ViewBuilder private var chipFill: some View {
        if on { Capsule().fill(theme.tint(scheme)) } else { ShPanelFill(shape: Capsule()) }
    }
}

struct EmptyNote: View {
    let title: String, text: String
    var body: some View {
        VStack(spacing: 6) {
            Text(title).font(.headline)
            Text(text).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 40)
        .listRowSeparator(.hidden).listRowBackground(Color.clear)
    }
}
