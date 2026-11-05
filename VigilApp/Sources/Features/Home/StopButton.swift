import SwiftUI

/// Stops every drum and leaves the tonal pad sounding, set apart from the strip so it is never
/// hit by accident.
struct StopButton: View {
    let action: () -> Void

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Button(action: action) {
            Image(systemName: "stop.fill")
                .font(.system(size: 18, weight: .semibold))
                .frame(width: 30, height: 30)
        }
        .glassButton(isOn: true, tint: PadColor.coral.color(scheme), shape: .circle)
        .controlSize(.extraLarge)
        .help("Corta todos os drums")
        .accessibilityLabel("Parar drums")
    }
}
