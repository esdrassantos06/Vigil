import Pow
import SwiftUI

/// Stops every drum and leaves the tonal pad sounding, set apart from the strip so it is never
/// hit by accident.
struct StopButton: View {
    let action: () -> Void

    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var presses = 0

    var body: some View {
        Button {
            action()
            presses += 1
        } label: {
            Image(systemName: "stop.fill")
                .font(.system(size: 18, weight: .semibold))
                .frame(width: 30, height: 30)
        }
        .glassButton(isOn: true, tint: PadColor.coral.color(scheme), shape: .circle)
        .controlSize(.extraLarge)
        .changeEffect(.shake(rate: .fast), value: presses, isEnabled: !reduceMotion)
        .help("Corta todos os drums")
        .accessibilityLabel("Parar drums")
    }
}
