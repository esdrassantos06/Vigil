import SwiftUI

/// Light hanging in the haze behind the glass: each drum pad's colour above its column and the
/// flame's glow behind the notes. It gives the glass something to bend. Static: it redraws only
/// when a pad colour changes or a note starts or stops, never per frame or per hit.
struct StageHaze: View {
    /// The eight pad colours in grid order, nil for an empty pad.
    let padColors: [Color?]
    let isNoteSounding: Bool
    /// Whether the notes sit above the drums (portrait) instead of beside them.
    let isPortrait: Bool

    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        if !reduceTransparency {
            GeometryReader { proxy in
                let size = proxy.size
                ZStack {
                    flameGlow(in: size)
                    ForEach(Array(padColors.enumerated()), id: \.offset) { index, color in
                        if let color { padGlow(color, index: index, in: size) }
                    }
                }
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }

    /// Dark stages take light additively; on a light ground the haze is a faint tint instead.
    private var strength: Double { scheme == .dark ? 1 : 0.45 }

    private func flameGlow(in size: CGSize) -> some View {
        let center = isPortrait
            ? UnitPoint(x: 0.5, y: 0.32)
            : UnitPoint(x: 0.22, y: 0.55)
        return RadialGradient(
            colors: [theme.accent.opacity((isNoteSounding ? 0.34 : 0.12) * strength), .clear],
            center: center, startRadius: 0, endRadius: max(size.width, size.height) * 0.42
        )
    }

    /// One glow per pad, above the middle of its cell, so the column it lights is its own.
    private func padGlow(_ color: Color, index: Int, in size: CGSize) -> some View {
        let column = Double(index % 4)
        let row = Double(index / 4)
        let left = isPortrait ? 0.03 : 0.43
        let span = isPortrait ? 0.94 : 0.55
        let top = isPortrait ? 0.55 : 0.30
        let x = left + span * (column + 0.5) / 4
        let y = top + row * (isPortrait ? 0.2 : 0.36)
        return RadialGradient(
            colors: [color.opacity(0.26 * strength), .clear],
            center: UnitPoint(x: x, y: y), startRadius: 0, endRadius: size.width * 0.16
        )
    }
}
