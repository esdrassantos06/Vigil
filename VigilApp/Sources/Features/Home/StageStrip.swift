import SwiftUI

/// Everything a performer reaches for mid-song, on one glass strip: the sounding key, tempo
/// and its beat, the pad level, reverb and pulse, and the drum stop kept apart from the rest.
struct StageStrip: View {
    @Bindable var model: AppModel

    @Environment(\.theme) private var theme

    /// Two rows instead of one, for a narrow window such as iPad in portrait.
    var isCompact = false

    var body: some View {
        Group {
            if isCompact {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 0) {
                        readouts
                        Spacer(minLength: 16)
                        stop
                    }
                    HStack(spacing: 0) { controls }
                }
            } else {
                HStack(spacing: 0) {
                    readouts
                    seam
                    controls
                    Spacer(minLength: 28)
                    stop
                }
            }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 14)
        .glassPane(radius: Metrics.paneRadius)
    }

    private var readouts: some View {
        HStack(spacing: 0) {
            KeyReadout(note: model.tonal.activeNote, sharps: model.settings.sharps, major: model.settings.major)
                .frame(width: 112, alignment: .leading)
            seam
            tempo
        }
    }

    @ViewBuilder
    private var controls: some View {
        LevelSlider(title: "Pad", value: $model.settings.padMaster)
        seam
        LevelSlider(title: "Reverb", value: $model.settings.padReverb)
        seam
        pulse
    }

    private var stop: some View {
        StopButton { model.drums.stopAll() }
    }

    private var seam: some View {
        Rectangle()
            .fill(theme.line)
            .frame(width: 1, height: 56)
    }

    private var tempo: some View {
        VStack(alignment: .leading, spacing: 6) {
            StripLabel("Andamento", detail: model.settings.timeSignature.rawValue)
            HStack(alignment: .center, spacing: 12) {
                ZStack(alignment: .leading) {
                    // Holds the width of the widest tempo so 99 to 100 does not push Tap aside.
                    Text(verbatim: "300").hidden()
                    Text(verbatim: "\(Int(model.settings.bpm.rounded()))")
                        .foregroundStyle(model.metronome.isRunning ? theme.accent : theme.ink)
                        .contentTransition(.numericText())
                }
                .font(.system(size: 50, weight: .semibold).monospacedDigit())
                .tracking(-1.5)
                .lineLimit(1)
                .fixedSize()
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text("\(Int(model.settings.bpm.rounded())) BPM"))
                VStack(alignment: .leading, spacing: 8) {
                    BeatLights(
                        metronome: model.metronome,
                        beats: model.settings.timeSignature.beatsPerBar
                    )
                    HStack(spacing: 6) {
                        Button { model.tapTempo() } label: {
                            Text("Tap").frame(minWidth: 44)
                        }
                        .glassButton()
                        .help("Tap Tempo")
                        Button { model.metronome.toggle() } label: {
                            Image(systemName: model.metronome.isRunning ? "metronome.fill" : "metronome")
                        }
                        .glassButton(isOn: model.metronome.isRunning, tint: theme.accent, shape: .circle)
                        .help("Metrônomo")
                        .accessibilityLabel("Metrônomo")
                        Button("2x") { model.settings.doubleTime.toggle() }
                            .glassButton(isOn: model.settings.doubleTime, tint: theme.accent)
                            .help("Dobra o clique do metrônomo")
                    }
                    .controlSize(.large)
                    .fixedSize()
                }
            }
        }
        .padding(.horizontal, 20)
    }

    private var pulse: some View {
        VStack(alignment: .leading, spacing: 10) {
            Menu {
                Picker("", selection: $model.settings.pulseRate) {
                    ForEach(PulseRate.allCases, id: \.self) { Text(verbatim: $0.label).tag($0) }
                }
            } label: {
                StripLabel("Pulse", detail: model.settings.pulseRate.label)
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
            .disabled(model.settings.pulse == nil)
            .help("Divisão do pulse")
            SlidingPicker(label: "Pulse", selection: $model.settings.pulse,
                          options: [SlidingOption(value: PulseShape?.none, title: "Desligado")]
                              + PulseShape.allCases.map {
                                  SlidingOption(value: Optional($0), title: LocalizedStringKey($0.label))
                              })
                .fixedSize()
        }
        .padding(.horizontal, 16)
        .layoutPriority(1)
    }
}

/// The sounding note, large enough to read from across the stage, lit in the flame's colours.
private struct KeyReadout: View {
    let note: Note?
    let sharps: Bool
    let major: Bool

    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            StripLabel("Tom")
            Group {
                if let note {
                    Text(verbatim: note.label(sharps: sharps, major: major))
                        .foregroundStyle(LinearGradient(colors: [theme.flame[2], theme.accent],
                                                        startPoint: .top, endPoint: .bottom))
                } else {
                    Text(verbatim: "—")
                        .fontWeight(.ultraLight)
                        .foregroundStyle(theme.inkMuted)
                }
            }
            .font(.system(size: 58, weight: .heavy))
            .tracking(-1.5)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
        }
        .accessibilityElement(children: .combine)
    }
}

/// One beat light per beat of the bar, the downbeat wider. Polls the player clock only while
/// the metronome runs, since the beat is read from audio time rather than observed.
private struct BeatLights: View {
    let metronome: MetronomeEngine
    let beats: Int

    @Environment(\.theme) private var theme

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: !metronome.isRunning)) { _ in
            let current = metronome.isRunning ? metronome.beatInBar : -1
            HStack(spacing: 5) {
                ForEach(0..<beats, id: \.self) { beat in
                    Capsule()
                        .fill(beat == current ? theme.accent : theme.idle)
                        .frame(width: beat == 0 ? 22 : 14, height: 5)
                }
            }
        }
        .accessibilityHidden(true)
    }
}

/// A labelled percentage slider on the strip.
private struct LevelSlider: View {
    let title: LocalizedStringKey
    @Binding var value: Double

    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                StripLabel(title)
                Spacer(minLength: 8)
                Text(verbatim: "\(Int((value * 100).rounded()))%")
                    .font(.system(size: 13, weight: .medium).monospacedDigit())
                    .foregroundStyle(theme.ink)
            }
            Slider(value: $value, in: 0...1)
                .tint(theme.accent)
                .controlSize(.small)
                .accessibilityLabel(Text(title))
        }
        .frame(minWidth: 140, idealWidth: 160, maxWidth: 210)
        .padding(.horizontal, 16)
    }
}

/// Small caps label for a strip field, with an optional value after a middle dot.
struct StripLabel: View {
    let text: LocalizedStringKey
    var detail: String?

    @Environment(\.theme) private var theme

    init(_ text: LocalizedStringKey, detail: String? = nil) {
        self.text = text
        self.detail = detail
    }

    var body: some View {
        HStack(spacing: 4) {
            Text(text)
            if let detail { Text(verbatim: "· \(detail)") }
        }
        .font(.system(size: 10.5, weight: .semibold))
        .textCase(.uppercase)
        .tracking(1.3)
        .foregroundStyle(theme.inkMuted)
        .lineLimit(1)
        .fixedSize()
    }
}
