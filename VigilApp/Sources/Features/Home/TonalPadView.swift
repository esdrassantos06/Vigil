import SwiftUI

/// The twelve notes. The sounding one burns with the Vigil flame; the rest recede so the eye
/// lands on it at once.
struct TonalPadGrid: View {
    let activeNote: Note?
    let sharps: Bool
    let major: Bool
    /// The pad master level, which sets how high the flame burns.
    let intensity: Double
    /// Notes per row: 4 beside the drums, 6 when the notes sit above them.
    var columns = 4
    let keyHint: (Note) -> String?
    /// Fires on touch down; a latched pad toggles here.
    let onPress: (Note) -> Void
    /// Fires when the finger or pointer lifts; an unlatched pad stops here.
    let onRelease: (Note) -> Void

    @Environment(\.theme) private var theme

    /// Explicit rows: a LazyVGrid row will not stretch to the window height.
    private var rows: [[Note]] {
        stride(from: 0, to: Note.allCases.count, by: columns).map {
            Array(Note.allCases[$0..<min($0 + columns, Note.allCases.count)])
        }
    }

    var body: some View {
        VStack(spacing: Metrics.padGap) {
            ForEach(rows, id: \.self) { row in
                HStack(spacing: Metrics.padGap) {
                    ForEach(row, id: \.self) { pad($0) }
                }
            }
        }
        .frame(maxHeight: .infinity)
    }

    private func pad(_ note: Note) -> some View {
        let isActive = activeNote == note
        let recedes = activeNote != nil && !isActive
        let shape = RoundedRectangle(cornerRadius: Metrics.noteRadius, style: .continuous)
        let label = note.label(sharps: sharps, major: major)
        return ZStack(alignment: .bottomLeading) {
            ZStack {
                if isActive {
                    NoteFlame(intensity: intensity)
                        .aspectRatio(224 / 492, contentMode: .fit)
                        .padding(.top, 26)
                        .padding(.bottom, 6)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                        .transition(.opacity)
                }
            }
            // Lighting and stopping flicker; when another note takes over the old flame goes at
            // once, so the eye only follows the new one.
            .animation(isActive || activeNote == nil ? .easeOut(duration: 0.3) : nil, value: isActive)
            VStack(alignment: .leading, spacing: 0) {
                Group {
                    if isActive {
                        HStack(spacing: 0) {
                            Text(verbatim: keyHint(note).map { "\($0) · " } ?? "")
                            Text("tocando")
                        }
                    } else {
                        Text(verbatim: keyHint(note) ?? " ")
                    }
                }
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(isActive ? theme.accent : theme.inkMuted)
                Spacer(minLength: 4)
                Text(verbatim: label)
                    .font(.system(size: 30, weight: .bold))
                    .tracking(-0.5)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .foregroundStyle(isActive ? theme.ink : theme.ink.opacity(0.82))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
        }
        .frame(maxWidth: .infinity, minHeight: 64, maxHeight: .infinity, alignment: .bottomLeading)
        .background(isActive ? AnyShapeStyle(activeFill) : AnyShapeStyle(theme.surface.opacity(0.7)), in: shape)
        .overlay(shape.strokeBorder(isActive ? theme.accent.opacity(0.6) : theme.line, lineWidth: 1))
        .contentShape(shape)
        .opacity(recedes ? 0.72 : 1)
        .onLongPressGesture(minimumDuration: .infinity) {} onPressingChanged: { isDown in
            isDown ? onPress(note) : onRelease(note)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { onPress(note) }
        .accessibilityLabel(Text(verbatim: label))
        .accessibilityAddTraits(isActive ? [.isSelected] : [])
    }

    private var activeFill: LinearGradient {
        LinearGradient(colors: [theme.accent.opacity(0.32), theme.surface.opacity(0.4)],
                       startPoint: .bottom, endPoint: .top)
    }
}

/// Under the notes: whether a note latches or plays only while held, and the crossfade time.
struct TonalFooter: View {
    @Binding var latch: Bool
    let crossfade: Double

    @Environment(\.theme) private var theme

    var body: some View {
        HStack {
            SlidingPicker(label: "Ao soltar a tecla", selection: $latch, options: [
                SlidingOption(value: true, title: "Travar", symbol: "lock.fill"),
                SlidingOption(value: false, title: "Segurar", symbol: "hand.point.up.left.fill"),
            ])
            Spacer(minLength: 8)
            StripLabel("Crossfade", detail: crossfade.formatted(.number.precision(.fractionLength(1))) + " s")
        }
    }
}

#Preview("Notas — com nota ativa") {
    TonalPadGrid(activeNote: .D, sharps: true, major: true, intensity: 0.8,
                 keyHint: { _ in "S" }, onPress: { _ in }, onRelease: { _ in })
        .environment(\.theme, .dark)
        .padding()
        .background(Theme.dark.bg)
        .frame(width: 520, height: 520)
}
