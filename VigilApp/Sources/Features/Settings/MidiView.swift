import SwiftUI

struct MidiView: View {
    @Bindable var model: AppModel
    let onClose: () -> Void

    @Environment(\.theme) private var theme

    var body: some View {
        Sheet("MIDI", onClose: {
            model.learning = nil
            onClose()
        }) {
            inputs
            ForEach(MidiTarget.sections, id: \.title) { section in
                mappings(LocalizedStringKey(section.title), section.targets)
            }
        } footer: {
            footer
        }
        .frame(width: 560, height: 640)
        // Without focus .onKeyPress never fires.
        .focusable()
        .focusEffectDisabled()
        .onKeyPress(phases: .down) { press in
            guard model.learning != nil, let character = press.characters.first else {
                return .ignored
            }
            return model.handleKey(character) ? .handled : .ignored
        }
    }

    private var inputs: some View {
        Panel("Entradas MIDI") {
            if model.midi.sources.isEmpty {
                Text("Nenhum dispositivo. Conecte um controlador: a lista atualiza sozinha.")
                    .font(.system(size: 13))
                    .foregroundStyle(theme.inkMuted)
            } else {
                ForEach(model.midi.sources) { source in
                    Toggle(source.name, isOn: Binding(
                        get: { !model.midiConfig.disabledInputs.contains(source.name) },
                        set: { model.setMidiInput(source, enabled: $0) }
                    ))
                    .font(.system(size: 13))
                }
            }

            HStack {
                Text("Canal MIDI")
                    .font(.system(size: 13))
                    .foregroundStyle(theme.ink)
                Spacer()
                Stepper(
                    value: Binding(
                        get: { model.midiConfig.channel },
                        set: { model.midiConfig.channel = $0 }
                    ),
                    in: 1...16
                ) {
                    Text("\(model.midiConfig.channel)")
                        .font(.system(size: 13).monospacedDigit())
                        .foregroundStyle(theme.inkMuted)
                }
                .fixedSize()
            }
        }
    }

    private func mappings(_ title: LocalizedStringKey, _ targets: [MidiTarget]) -> some View {
        Panel(title) {
            ForEach(targets, id: \.key) { target in
                row(target)
            }
        }
    }

    private func row(_ target: MidiTarget) -> some View {
        HStack(spacing: 8) {
            Text(LocalizedStringKey(target.label))
                .font(.system(size: 13))
                .foregroundStyle(theme.ink)
            Spacer(minLength: 8)
            slot(target, keyboard: true)
            slot(target, keyboard: false)
        }
        .frame(minHeight: Metrics.minTarget)
    }

    private func slot(_ target: MidiTarget, keyboard: Bool) -> some View {
        let binding = model.midiConfig.binding(for: target, keyboard: keyboard)
        let isLearning = model.learning?.target == target
            && model.learning?.keyboard == keyboard
        return HStack(spacing: 4) {
            Button {
                if isLearning {
                    model.learning = nil
                } else {
                    model.startLearning(target, keyboard: keyboard)
                }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: keyboard ? "keyboard" : "pianokeys")
                        .font(.system(size: 10))
                    Text(isLearning ? "Aguardando…" : LocalizedStringKey(binding?.label ?? "Learn"))
                        .font(.system(size: 12).monospacedDigit())
                        .lineLimit(1)
                }
                .foregroundStyle(
                    isLearning ? theme.accent : (binding == nil ? theme.inkMuted : theme.ink)
                )
                .padding(.horizontal, 9)
                .padding(.vertical, 6)
                .frame(minWidth: 92)
                .background(
                    isLearning ? theme.accent.opacity(0.14) : theme.surface2,
                    in: RoundedRectangle(cornerRadius: Metrics.controlRadius)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Metrics.controlRadius)
                        .stroke(isLearning ? theme.accent : theme.line, lineWidth: 1)
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(keyboard ? "Tecla do computador" : "Nota ou CC do controlador")

            Button { model.midiConfig.clear(target, keyboard: keyboard) } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .semibold))
            }
            .buttonStyle(IconButtonStyle(diameter: 20))
            .opacity(binding == nil ? 0 : 1)
            .disabled(binding == nil)
            .help("Limpar")
            .accessibilityLabel("Limpar")
        }
    }

    private var footer: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(theme.line)
                .frame(height: 1)
            HStack(spacing: 10) {
                Button("Limpar mapeamentos") { model.midiConfig.clearAll() }
                Button("Restaurar teclas padrão") { model.midiConfig.restoreDefaults() }
                Spacer(minLength: 0)
            }
            .buttonStyle(.bordered)
            .font(.system(size: 12))
            .padding(.horizontal, Metrics.zoneGap)
            .padding(.vertical, 12)
        }
    }
}

#Preview("MIDI") {
    MidiView(model: AppModel(), onClose: {})
        .environment(\.theme, .dark)
}
