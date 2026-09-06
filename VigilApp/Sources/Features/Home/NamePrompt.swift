import SwiftUI

struct NamePrompt: View {
    let title: String
    let placeholder: String
    @State private var name: String
    let onCancel: () -> Void
    let onConfirm: (String) -> Void

    @Environment(\.theme) private var theme
    @FocusState private var isFocused: Bool

    init(
        title: String,
        placeholder: String,
        initial: String = "",
        onCancel: @escaping () -> Void,
        onConfirm: @escaping (String) -> Void
    ) {
        self.title = title
        self.placeholder = placeholder
        self.onCancel = onCancel
        self.onConfirm = onConfirm
        _name = State(initialValue: initial)
    }

    private var trimmed: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 9) {
                FlameMark()
                    .fill(theme.accent)
                    .frame(width: 8, height: 18)
                Text(title)
                    .font(.system(size: 22, weight: .regular, design: .serif))
                    .foregroundStyle(theme.ink)
            }

            TextField(placeholder, text: $name)
                .textFieldStyle(.plain)
                .font(.system(size: 15))
                .foregroundStyle(theme.ink)
                .padding(12)
                .background(theme.surface2, in: RoundedRectangle(cornerRadius: Metrics.controlRadius))
                .overlay(
                    RoundedRectangle(cornerRadius: Metrics.controlRadius)
                        .stroke(theme.line, lineWidth: 1)
                )
                .focused($isFocused)
                .onSubmit { if !trimmed.isEmpty { onConfirm(trimmed) } }

            HStack {
                Spacer()
                Button("Cancelar", action: onCancel)
                    .buttonStyle(.plain)
                    .foregroundStyle(theme.inkMuted)
                Button("Salvar") { onConfirm(trimmed) }
                    .buttonStyle(.plain)
                    .foregroundStyle(trimmed.isEmpty ? theme.inkMuted : theme.accent)
                    .disabled(trimmed.isEmpty)
            }
            .font(.system(size: 15, weight: .medium))
        }
        .padding(Metrics.zoneGap)
        .frame(width: 380)
        .background(theme.bg)
        // Without focus here the keystroke falls through to the home handler and fires a pad.
        .task { isFocused = true }
    }
}

#Preview("Nome do kit") {
    NamePrompt(title: "Salvar kit", placeholder: "Ex.: Meu Kit", onCancel: {}, onConfirm: { _ in })
        .environment(\.theme, .dark)
}
