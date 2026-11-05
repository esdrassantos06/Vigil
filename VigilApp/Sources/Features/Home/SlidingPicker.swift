import SwiftUI

/// One option of a `SlidingPicker`.
struct SlidingOption<Value: Hashable>: Identifiable {
    let value: Value
    let title: LocalizedStringKey
    var symbol: String?

    var id: Value { value }
}

/// A segmented choice whose lit thumb slides to the option in use, so the state reads by
/// position as well as by colour. The thumb's capsule is inset by exactly the track padding,
/// which keeps both curves concentric.
struct SlidingPicker<Value: Hashable>: View {
    let label: LocalizedStringKey
    @Binding var selection: Value
    let options: [SlidingOption<Value>]

    @Environment(\.theme) private var theme
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var thumb

    private static var inset: CGFloat { 3 }

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options) { option($0) }
        }
        .padding(Self.inset)
        .glassPane(Capsule())
        .opacity(isEnabled ? 1 : 0.5)
        .animation(reduceMotion ? nil : .snappy(duration: 0.22), value: selection)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(label))
        .accessibilityValue(Text(options.first { $0.value == selection }?.title ?? ""))
        .accessibilityAdjustableAction { direction in
            guard let index = options.firstIndex(where: { $0.value == selection }) else { return }
            switch direction {
            case .increment: selection = options[min(index + 1, options.count - 1)].value
            case .decrement: selection = options[max(index - 1, 0)].value
            @unknown default: break
            }
        }
    }

    private func option(_ option: SlidingOption<Value>) -> some View {
        let isOn = selection == option.value
        return Button { selection = option.value } label: {
            Group {
                if let symbol = option.symbol {
                    Label(option.title, systemImage: symbol)
                } else {
                    Text(option.title)
                }
            }
            .font(.system(size: 12, weight: .semibold))
            .lineLimit(1)
            .foregroundStyle(isOn ? theme.accent : theme.inkMuted)
            .padding(.horizontal, 12)
            .frame(height: 28)
            .background {
                if isOn {
                    Capsule()
                        .fill(theme.accent.opacity(0.18))
                        .overlay(Capsule().strokeBorder(theme.accent.opacity(0.5), lineWidth: 1))
                        .matchedGeometryEffect(id: "thumb", in: thumb)
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(option.title)
    }
}

#Preview("Seletor deslizante") {
    @Previewable @State var latch = true
    SlidingPicker(label: "Ao soltar a tecla", selection: $latch, options: [
        SlidingOption(value: true, title: "Travar", symbol: "lock.fill"),
        SlidingOption(value: false, title: "Segurar", symbol: "hand.point.up.left.fill"),
    ])
    .padding()
    .background(Theme.dark.bg)
    .environment(\.theme, .dark)
}
