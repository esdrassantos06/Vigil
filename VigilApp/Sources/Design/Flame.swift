import SwiftUI

/// The Vigil flame burning inside the sounding note. It appears at once (the note is already
/// sounding) and only its idle flicker is animated, which Reduce Motion holds still.
struct NoteFlame: View {
    /// 0...1, the pad's master level: a quieter pad burns lower.
    var intensity: Double = 1

    @Environment(\.theme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let height = 0.55 + 0.45 * intensity
        PhaseAnimator(reduceMotion ? [1.0] : [1.0, 1.06, 0.97, 1.03]) { phase in
            ZStack(alignment: .bottom) {
                FlameMark()
                    .fill(LinearGradient(colors: [theme.accent.opacity(0.7), theme.accent, theme.flame[2]],
                                         startPoint: .top, endPoint: .bottom))
                    .shadow(color: theme.accent.opacity(0.65), radius: 18)
                FlameMark()
                    .fill(theme.flame[2])
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .scaleEffect(x: 0.42, y: 0.46, anchor: .bottom)
                    .opacity(0.85)
            }
            .scaleEffect(x: 1, y: height * phase, anchor: .bottom)
        } animation: { _ in .easeInOut(duration: 0.45) }
        .blendMode(.screen)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

#Preview("Chama") {
    NoteFlame()
        .frame(width: 70, height: 140)
        .padding(40)
        .background(Theme.dark.bg)
        .environment(\.theme, .dark)
}
