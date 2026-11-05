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
                    hertzRow("Passa-alta", value: $model.settings.highpass, range: Settings.highpassRange)
                    secondsRow("Crossfade", value: $model.settings.crossfade)
                    percentRow("Reverb", value: $model.settings.padReverb)
                    pulseRow
                    percentRow("Profundidade", value: $model.settings.pulseDepth)
                        .disabled(model.settings.pulse == nil)
                    decibelRow("Graves", value: $model.settings.padLow, range: Settings.toneRange)
                    decibelRow("Médios", value: $model.settings.padMid, range: Settings.toneRange)
                    decibelRow("Agudos", value: $model.settings.padHigh, range: Settings.toneRange)
                    Toggle("Compressor", isOn: $model.settings.padCompressor)
                        .font(.system(size: 13))
                    Group {
                        decibelRow("Limiar", value: $model.settings.compressorThreshold, range: Settings.thresholdRange)
                        decibelRow("Ganho", value: $model.settings.compressorGain, range: Settings.makeupRange)
                    }
                    .disabled(!model.settings.padCompressor)
                    picker("Ao soltar a tecla", selection: $model.settings.padLatch,
                           options: [(true, "Continua tocando"), (false, "Para o pad")])
                    Toggle("Pedal de sustain invertido", isOn: $model.settings.sustainInverted)
                        .font(.system(size: 13))
                        .disabled(model.settings.padLatch)
                }

                Panel("Camadas") {
                    percentRow("Principal", value: $model.settings.padMainLevel)
                    ForEach(model.settings.padLayers.indices, id: \.self) { layerRow($0) }
                    Button("Adicionar camada") {
                        let sound = model.catalog.padSoundList.first { $0.id != model.tonal.soundID }?.id ?? model.tonal.soundID
                        model.settings.padLayers.append(PadLayer(soundID: sound, level: 0.8))
                    }
                    .buttonStyle(.bordered)
                    .font(.system(size: 13))
                    .disabled(model.settings.padLayers.count >= Settings.maxExtraLayers)
                }

                Panel("Drum Pads") {
                    percentRow("Master", value: $model.settings.drumMaster)
                    panRow("Pan", value: $model.settings.drumPan)
                    Text("O pan é único para os 8 pads.")
                        .font(.system(size: 11))
                        .foregroundStyle(theme.inkMuted)
                    hertzRow("Passa-alta", value: $model.settings.drumHighpass, range: Settings.highpassRange)
                    hertzRow("Cutoff", value: $model.settings.drumCutoff, range: Settings.drumCutoffRange)
                    HStack {
                        Text("Reverb").font(.system(size: 13)).foregroundStyle(theme.ink)
                        Spacer()
                        Picker("", selection: $model.settings.drumReverb) {
                            ForEach(DrumReverb.allCases, id: \.self) { Text(LocalizedStringKey($0.label)).tag($0) }
                        }
                        .labelsHidden()
                        .frame(width: 140)
                    }
                    percentRow("Retorno do reverb", value: $model.settings.drumReverbLevel)
                }

                Panel("Saída") {
                    row("Atraso", "\(Int((model.settings.outputDelay * 1_000).rounded())) ms",
                        Slider(value: $model.settings.outputDelay, in: Settings.outputDelayRange))
                    Text("Atrasa tudo que o Vigil toca, para alinhar com outro equipamento.")
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
                    themeRow("Escuros", AppTheme.darkThemes)
                    themeRow("Claros", AppTheme.lightThemes)
                    Button { model.theme = .system } label: {
                        HStack(spacing: 8) {
                            Image(systemName: model.theme == .system ? "checkmark.circle.fill" : "circle")
                            Text("Sistema")
                        }
                        .font(.system(size: 13))
                        .foregroundStyle(model.theme == .system ? theme.accent : theme.inkMuted)
                    }
                    .buttonStyle(.plain)
                }
        }
        .frame(width: 460, height: 640)
    }

    private func themeRow(_ title: LocalizedStringKey, _ options: [AppTheme]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ZoneLabel(title)
            HStack(spacing: 8) {
                ForEach(options) { option in
                    Button { model.theme = option } label: {
                        ThemeSwatch(option: option, isSelected: model.theme == option)
                    }
                    .buttonStyle(.plain)
                    .help(LocalizedStringKey(option.name))
                }
                Spacer(minLength: 0)
            }
        }
    }

    /// Pulse follows the metronome tempo and restarts on its downbeat.
    private var pulseRow: some View {
        HStack {
            Text("Pulse").font(.system(size: 13)).foregroundStyle(theme.ink)
            Spacer()
            Picker("", selection: $model.settings.pulse) {
                Text("Desligado").tag(PulseShape?.none)
                ForEach(PulseShape.allCases, id: \.self) { Text(LocalizedStringKey($0.label)).tag(PulseShape?.some($0)) }
            }
            .labelsHidden()
            .frame(width: 120)
            Picker("", selection: $model.settings.pulseRate) {
                ForEach(PulseRate.allCases, id: \.self) { Text(verbatim: $0.label).tag($0) }
            }
            .labelsHidden()
            .frame(width: 80)
            .disabled(model.settings.pulse == nil)
        }
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

    /// Log scale: pitch is heard logarithmically, so a linear slider spends most of its travel
    /// in the top octave where almost nothing changes.
    private func hertzRow(_ label: LocalizedStringKey, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        let hz = value.wrappedValue
        let readout = hz >= 1_000
            ? String(format: "%.1f kHz", hz / 1_000)
            : String(format: "%.0f Hz", hz)
        let logarithmic = Binding(
            get: { log10(max(range.lowerBound, value.wrappedValue)) },
            set: { value.wrappedValue = min(range.upperBound, pow(10, $0)) }
        )
        return row(label, "\(readout)",
                   Slider(value: logarithmic,
                          in: log10(range.lowerBound)...log10(range.upperBound)))
    }

    private func decibelRow(_ label: LocalizedStringKey, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        row(label, "\(String(format: "%+.0f dB", value.wrappedValue))", Slider(value: value, in: range, step: 1))
    }

    /// Bindings go through the index each time: removing a layer must not read past the end.
    private func layerRow(_ index: Int) -> some View {
        let layers = $model.settings.padLayers
        let level = Binding(
            get: { layers.wrappedValue[safe: index]?.level ?? 0 },
            set: { if layers.wrappedValue.indices.contains(index) { layers.wrappedValue[index].level = $0 } }
        )
        let sound = Binding(
            get: { layers.wrappedValue[safe: index]?.soundID ?? "" },
            set: { if layers.wrappedValue.indices.contains(index) { layers.wrappedValue[index].soundID = $0 } }
        )
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Picker("", selection: sound) {
                    ForEach(model.catalog.padSoundList) { Text(model.t(dynamic: $0.name)).tag($0.id) }
                }
                .labelsHidden()
                Button {
                    if layers.wrappedValue.indices.contains(index) { layers.wrappedValue.remove(at: index) }
                } label: {
                    Image(systemName: "minus.circle")
                }
                .buttonStyle(.plain)
                .foregroundStyle(theme.inkMuted)
                .help("Remover camada")
                .accessibilityLabel("Remover camada")
            }
            Slider(value: level).frame(height: Metrics.minTarget)
        }
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
