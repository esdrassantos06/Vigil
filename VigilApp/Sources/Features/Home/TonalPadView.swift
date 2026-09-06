import SwiftUI

struct TonalPadGrid: View {
    let activeNote: Note?
    let sharps: Bool
    let major: Bool
    let onToggle: (Note) -> Void

    @Environment(\.theme) private var theme

    /// Explicit rows: a LazyVGrid row will not stretch to the window height.
    private var rows: [[Note]] {
        stride(from: 0, to: Note.allCases.count, by: 3).map {
            Array(Note.allCases[$0..<min($0 + 3, Note.allCases.count)])
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
        return Button { onToggle(note) } label: {
            Text(note.label(sharps: sharps, major: major))
                .font(.system(size: 22, weight: .regular, design: .serif))
                .foregroundStyle(isActive ? theme.accent : theme.ink)
                .frame(maxWidth: .infinity, minHeight: 64, maxHeight: .infinity)
                .background(isActive ? theme.accent.opacity(0.16) : theme.surface)
                .clipShape(RoundedRectangle(cornerRadius: Metrics.padRadius))
                .overlay(
                    RoundedRectangle(cornerRadius: Metrics.padRadius)
                        .stroke(isActive ? theme.accent : theme.line, lineWidth: isActive ? 1.5 : 1)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(note.label(sharps: sharps, major: major))
        .accessibilityAddTraits(isActive ? [.isSelected] : [])
    }
}

struct TransportPanel: View {
    let activeNote: Note?
    let sharps: Bool
    let major: Bool
    let onStopDrums: () -> Void

    @Environment(\.theme) private var theme

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                ZoneLabel("Tom")
                HStack(spacing: 8) {
                    Text(activeNote.map { $0.label(sharps: sharps, major: major) } ?? "—")
                        .font(.system(size: 34, weight: .regular, design: .serif))
                        .foregroundStyle(activeNote == nil ? theme.inkMuted : theme.ink)
                    if activeNote != nil {
                        Circle()
                            .fill(theme.accent)
                            .frame(width: 9, height: 9)
                    }
                }
            }
            Spacer(minLength: 0)
            StopButton(action: onStopDrums)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(theme.surface)
    }
}

struct StepperSelector: View {
    let title: String
    let value: String
    let onPrevious: () -> Void
    let onNext: () -> Void

    @Environment(\.theme) private var theme

    var body: some View {
        HStack(spacing: 8) {
            ZoneLabel(LocalizedStringKey(title))
                .frame(width: 68, alignment: .leading)

            arrow("chevron.left", action: onPrevious)

            Text(value)
                .font(.system(size: 19, weight: .regular, design: .serif))
                .foregroundStyle(theme.ink)
                .frame(maxWidth: .infinity)
                .lineLimit(1)

            arrow("chevron.right", action: onNext)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .card(theme.surface, radius: Metrics.controlRadius)
    }

    private func arrow(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(theme.inkMuted)
                .frame(width: Metrics.minTarget, height: 32)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

#Preview("Pad tonal — com nota ativa") {
    TonalPadGrid(activeNote: .C, sharps: true, major: true, onToggle: { _ in })
        .environment(\.theme, .dark)
        .padding()
        .background(Theme.dark.bg)
        .frame(width: 260)
}

#Preview("Transporte") {
    TransportPanel(
        activeNote: .Fs,
        sharps: true,
        major: true,
        onStopDrums: {}
    )
    .environment(\.theme, .dark)
    .padding()
    .background(Theme.dark.bg)
    .frame(width: 260)
}

#Preview("Seletor") {
    StepperSelector(title: "Pad", value: "Shimmer", onPrevious: {}, onNext: {})
        .environment(\.theme, .dark)
        .padding()
        .background(Theme.dark.bg)
        .frame(width: 320)
}
