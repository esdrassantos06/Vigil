import SwiftUI

struct SettingsView: View {
    @Bindable var model: AppModel
    let onClose: () -> Void
    let onOpenMidi: () -> Void

    @Environment(\.theme) private var theme

    var body: some View {
        Sheet("Configurações", onClose: onClose) {
                Panel("Pad") {
                    percentRow("Master", value: $model.settings.padMaster)
                    panRow("Pan", value: $model.settings.padPan)
                    hertzRow("Cutoff", value: $model.settings.cutoff, range: Settings.cutoffRange)
                    hertzRow("HPF", value: $model.settings.highpass, range: Settings.highpassRange)
                    secondsRow("Crossfade", value: $model.settings.crossfade)
                }

                Panel("Drum Pads") {
                    percentRow("Master", value: $model.settings.drumMaster)
                    panRow("Pan", value: $model.settings.drumPan)
                    Text("O pan é único para os 8 pads.")
                        .font(.system(size: 11))
                        .foregroundStyle(theme.inkMuted)
                }

                Panel("Metrônomo") {
                    row("Tempo", "\(Int(model.settings.bpm)) BPM",
                        Slider(value: $model.settings.bpm, in: Settings.bpmRange, step: 1))

                    HStack(spacing: 10) {
                        Button(model.metronome.isRunning ? "Parar" : "Iniciar") {
                            model.metronome.toggle()
                        }
                        Button("Tap Tempo") { model.tapTempo() }
                    }
                    .buttonStyle(.bordered)
                    .font(.system(size: 13))

                    HStack {
                        Text("Compasso").font(.system(size: 13)).foregroundStyle(theme.ink)
                        Spacer()
                        Picker("", selection: $model.settings.timeSignature) {
                            ForEach(TimeSignature.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                        }
                        .labelsHidden()
                        .frame(width: 100)
                    }

                    HStack {
                        Text("Som do click").font(.system(size: 13)).foregroundStyle(theme.ink)
                        Spacer()
                        Picker("", selection: $model.settings.clickSound) {
                            ForEach(ClickSound.allCases, id: \.self) { Text($0.label).tag($0) }
                        }
                        .labelsHidden()
                        .frame(width: 120)
                    }

                    Toggle("Acentuar 1", isOn: $model.settings.accentFirst)
                        .font(.system(size: 13))
                    Toggle("2x (dobra o clique)", isOn: $model.settings.doubleTime)
                        .font(.system(size: 13))

                    percentRow("Volume", value: $model.settings.metronomeVolume)
                    panRow("Pan", value: $model.settings.metronomePan)
                }

                Panel("MIDI") {
                    HStack(spacing: 4) {
                        Text(inputsLabel)
                        Text("· canal \(model.midiConfig.channel)")
                        Spacer()
                        Button("Abrir…", action: onOpenMidi)
                            .buttonStyle(.bordered)
                    }
                    .font(.system(size: 13))
                    .foregroundStyle(theme.inkMuted)
                    Text("Entradas, canal e MIDI Learn. No Mac, aparelhos Bluetooth entram pelo Audio MIDI Setup do sistema.")
                        .font(.system(size: 11))
                        .foregroundStyle(theme.inkMuted)
                }

                Panel("Notação dos Tons") {
                    picker("Acidente", selection: $model.settings.sharps,
                           options: [(true, "Sustenido (C#)"), (false, "Bemol (Db)")])
                    picker("Modo", selection: $model.settings.major,
                           options: [(true, "Maior (C)"), (false, "Menor (Am)")])
                }

                Panel("Idioma") {
                    Picker("", selection: $model.language) {
                        ForEach(Language.allCases, id: \.self) { option in
                            Text(option.label).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }

                Panel("Tema") {
                    Picker("", selection: $model.theme) {
                        ForEach(ThemePreference.allCases, id: \.self) { option in
                            Text(LocalizedStringKey(option.label)).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }
        }
        .frame(width: 460, height: 640)
    }

    private var inputsLabel: LocalizedStringKey {
        switch model.midi.sources.count {
        case 0: "Nenhuma entrada"
        case 1: "1 entrada"
        case let count: "\(count) entradas"
        }
    }

    private func row(_ label: LocalizedStringKey, _ readout: LocalizedStringKey, _ slider: some View) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                    .font(.system(size: 13))
                    .foregroundStyle(theme.ink)
                Spacer()
                Text(readout)
                    .font(.system(size: 13).monospacedDigit())
                    .foregroundStyle(theme.inkMuted)
            }
            slider.frame(height: Metrics.minTarget)
        }
    }

    private func percentRow(_ label: LocalizedStringKey, value: Binding<Double>) -> some View {
        row(label, "\(Int(value.wrappedValue * 100))%", Slider(value: value))
    }

    private func panRow(_ label: LocalizedStringKey, value: Binding<Double>) -> some View {
        let position = value.wrappedValue
        let readout: LocalizedStringKey = if abs(position) < 0.01 {
            "centro"
        } else if position < 0 {
            "E \(Int(abs(position) * 100))"
        } else {
            "D \(Int(position * 100))"
        }
        return row(label, readout, Slider(value: value, in: -1...1))
    }

    private func hertzRow(_ label: LocalizedStringKey, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        let hz = value.wrappedValue
        let readout = hz >= 1_000
            ? String(format: "%.1f kHz", hz / 1_000)
            : String(format: "%.0f Hz", hz)
        return row(label, "\(readout)", Slider(value: value, in: range))
    }

    private func secondsRow(_ label: LocalizedStringKey, value: Binding<Double>) -> some View {
        row(
            label,
            "\(String(format: "%.1f s", value.wrappedValue))",
            Slider(value: value, in: Settings.crossfadeRange)
        )
    }

    private func picker(
        _ label: LocalizedStringKey,
        selection: Binding<Bool>,
        options: [(Bool, String)]
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 13))
                .foregroundStyle(theme.ink)
            Picker("", selection: selection) {
                ForEach(options, id: \.0) { option in
                    Text(LocalizedStringKey(option.1)).tag(option.0)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
    }
}

#Preview("Configurações") {
    SettingsView(model: AppModel(), onClose: {}, onOpenMidi: {})
        .environment(\.theme, .dark)
}
