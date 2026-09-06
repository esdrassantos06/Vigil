import SwiftUI

/// Dim at rest: on a dark stage the eye should not be pulled by an idle control.
struct StopButton: View {
    let action: () -> Void

    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var scheme
    @State private var isPressed = false

    var body: some View {
        Button(action: action) {
            RoundedRectangle(cornerRadius: 3)
                .fill(isPressed ? PadColor.coral.color(scheme) : theme.inkMuted)
                .frame(width: 14, height: 14)
                .frame(width: Metrics.minTarget, height: Metrics.minTarget)
                .background(theme.surface, in: RoundedRectangle(cornerRadius: Metrics.controlRadius))
                .overlay(
                    RoundedRectangle(cornerRadius: Metrics.controlRadius)
                        .stroke(theme.line, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .onLongPressGesture(minimumDuration: 0, pressing: { isPressed = $0 }, perform: {})
        .help("Corta todos os drums")
        .accessibilityLabel("Parar drums")
    }
}
