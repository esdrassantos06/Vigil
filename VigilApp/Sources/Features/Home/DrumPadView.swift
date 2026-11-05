import Pow
import SwiftUI

struct DrumPadView: View {
    let pad: DrumPad
    let keyHint: String?
    let kits: [FactoryKit]
    let samples: [Sample]
    let onTap: () -> Void
    let onPickNative: (FactoryKit, Int) -> Void
    let onPickSample: (Sample) -> Void
    let onColor: (PadColor) -> Void
    let onVoicing: (PadVoicing) -> Void
    let onClear: () -> Void
    let onVolume: (Double) -> Void
    let onTrim: (ClosedRange<Double>) -> Void
    let onReverbSend: (Double) -> Void

    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pickingColor = false
    @State private var trimming = false

    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: Metrics.padRadius, style: .continuous) }
    private var tint: Color { pad.color.color(scheme) }

    var body: some View {
        VStack(spacing: 0) {
            Button(action: onTap) { face }
                .buttonStyle(.plain)
                .contextMenu { menu }
                // One popover per view: the colour picker already sits on the card.
                .popover(isPresented: $trimming, arrowEdge: .bottom) {
                    TrimEditor(trim: pad.trim, reverbSend: pad.reverbSend,
                               onChange: onTrim, onReverbSend: onReverbSend)
                }
            if pad.isAssigned { volumeStrip }
        }
        .background(alignment: .top) { if pad.isAssigned { beam } }
        .background(tint.opacity(pad.isFlashing ? 0.85 : 0), in: shape)
        .background(theme.bg.opacity(0.85), in: shape)
        .clipShape(shape)
        .overlay(shape.strokeBorder(border, lineWidth: pad.isFlashing ? 1.5 : 1))
        .changeEffect(.shine(angle: .degrees(100), duration: 0.45), value: pad.isFlashing,
                      isEnabled: pad.isFlashing && !reduceMotion)
        .conditionalEffect(.pushDown, condition: pad.isFlashing && !reduceMotion)
        .popover(isPresented: $pickingColor, arrowEdge: .bottom) {
            ColorSwatchPicker(selected: pad.color) { color in
                onColor(color)
                pickingColor = false
            }
        }
        .accessibilityLabel(pad.name.map { "\(pad.label), \($0)" } ?? "\(pad.label), vazio")
    }

    /// The pad's light cast down through haze. Only its opacity changes on a hit, so a
    /// trigger never re-renders a gradient or a blur.
    private var beam: some View {
        StageBeam()
            .fill(LinearGradient(colors: [tint.opacity(0.9), tint.opacity(0.25), tint.opacity(0)],
                                 startPoint: .top, endPoint: .bottom))
            .opacity(pad.isFlashing ? 1 : 0.6)
            .accessibilityHidden(true)
    }

    private var face: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Circle()
                    .fill(pad.isAssigned ? tint : theme.line)
                    .frame(width: 8, height: 8)
                Text(pad.label)
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(0.8)
                    .foregroundStyle(pad.isFlashing ? hitInk : theme.inkMuted)
                Spacer(minLength: 0)
                if let keyHint {
                    Text(verbatim: keyHint)
                        .font(.system(size: 11, weight: .semibold).monospacedDigit())
                        .foregroundStyle(theme.inkMuted)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(theme.line, lineWidth: 1))
                }
            }
            Spacer(minLength: 8)
            Group {
                if let name = pad.name {
                    Text(name)
                        .font(.system(size: 21, weight: .semibold))
                        .foregroundStyle(pad.isFlashing ? hitInk : theme.ink)
                } else {
                    Image(systemName: "plus")
                        .font(.system(size: 20, weight: .light))
                        .foregroundStyle(theme.inkMuted)
                        .frame(maxWidth: .infinity)
                }
            }
            .lineLimit(2)
            .multilineTextAlignment(.leading)
            if pad.name == nil { Spacer(minLength: 8) }
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, pad.isAssigned ? 4 : 14)
        .frame(maxWidth: .infinity, minHeight: 80, maxHeight: .infinity, alignment: .topLeading)
        .contentShape(Rectangle())
    }

    private var volumeStrip: some View {
        LevelBar(value: pad.volume, tint: pad.isFlashing ? hitInk : tint, onChange: onVolume)
            .accessibilityLabel(Text("Volume \(pad.label)"))
            .padding(.horizontal, 16)
            .padding(.bottom, 10)
    }

    /// Ink on a lit pad, where the pad's own colour is the ground.
    private var hitInk: Color { Color.black.opacity(0.8) }

    private var border: Color {
        guard pad.isAssigned else { return theme.line }
        return tint.opacity(pad.isFlashing ? 1 : 0.35)
    }

    @ViewBuilder
    private var menu: some View {
        Button("Cor do pad…") { pickingColor = true }
        if pad.isAssigned {
            Button("Recortar…") { trimming = true }
        }

        Menu("Ao bater de novo") {
            Button {
                onVoicing(.poly)
            } label: {
                Label("Sobrepor", systemImage: pad.voicing == .poly ? "checkmark" : "square.stack")
            }
            Button {
                onVoicing(.mono)
            } label: {
                Label("Reiniciar", systemImage: pad.voicing == .mono ? "checkmark" : "arrow.counterclockwise")
            }
        }

        Menu("Instrumentos nativos") {
            ForEach(kits) { kit in
                Menu(kit.name) {
                    ForEach(Array(kit.slots.enumerated()), id: \.offset) { index, slot in
                        Button(slot.name) { onPickNative(kit, index) }
                    }
                }
            }
        }

        Menu("Samples") {
            if samples.isEmpty {
                Text("Nenhum sample importado")
            } else {
                ForEach(samples) { sample in
                    Button(sample.displayName) { onPickSample(sample) }
                }
            }
        }

        if pad.isAssigned {
            Divider()
            Button("Limpar atribuição", role: .destructive, action: onClear)
        }
    }
}

/// A thin level line in the pad's colour that sets the volume by dragging along it.
struct LevelBar: View {
    let value: Double
    let tint: Color
    let onChange: (Double) -> Void

    @Environment(\.theme) private var theme

    var body: some View {
        GeometryReader { proxy in
            let width = max(proxy.size.width, 1)
            ZStack(alignment: .leading) {
                Capsule().fill(theme.ink.opacity(0.12))
                Capsule().fill(tint).frame(width: width * value)
            }
            .frame(height: 4)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { drag in
                onChange(min(max(drag.location.x / width, 0), 1))
            })
        }
        .frame(height: 20)
        .accessibilityElement()
        .accessibilityValue(Text(verbatim: "\(Int((value * 100).rounded()))%"))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: onChange(min(value + 0.05, 1))
            case .decrement: onChange(max(value - 0.05, 0))
            @unknown default: break
            }
        }
    }
}

/// A stage light's cone from a narrow source at the top edge to the full width below.
struct StageBeam: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX - rect.width * 0.12, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.midX + rect.width * 0.12, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX + rect.width * 0.1, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX - rect.width * 0.1, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

extension PadColor {
    var label: String {
        switch self {
        case .coral: "Coral"
        case .laranja: "Laranja"
        case .amarelo: "Amarelo"
        case .verde: "Verde"
        case .menta: "Menta"
        case .ceu: "Céu"
        case .indigo: "Índigo"
        case .violeta: "Violeta"
        case .magenta: "Magenta"
        }
    }
}


/// Start and end of the one-shot, as a share of its length, and the pad's reverb send.
struct TrimEditor: View {
    let trim: ClosedRange<Double>
    let reverbSend: Double
    let onChange: (ClosedRange<Double>) -> Void
    let onReverbSend: (Double) -> Void

    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Recorte")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(theme.ink)
            row("Início", value: trim.lowerBound, range: 0...0.98) { onChange($0...max(trim.upperBound, $0 + 0.02)) }
            row("Fim", value: trim.upperBound, range: 0.02...1) { onChange(min(trim.lowerBound, $0 - 0.02)...$0) }
            Button("Restaurar") { onChange(PadTrim.full) }
                .buttonStyle(.bordered)
                .disabled(trim == PadTrim.full)
            Divider()
            row("Reverb", value: reverbSend, range: 0...1, set: onReverbSend)
        }
        .font(.system(size: 13))
        .padding(14)
        .frame(width: 260)
    }

    private func row(_ label: LocalizedStringKey, value: Double, range: ClosedRange<Double>,
                     set: @escaping (Double) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(label).foregroundStyle(theme.ink)
                Spacer()
                Text(verbatim: "\(Int((value * 100).rounded()))%")
                    .monospacedDigit()
                    .foregroundStyle(theme.inkMuted)
            }
            Slider(value: Binding(get: { value }, set: set), in: range)
        }
    }
}

/// A popover rather than a submenu: macOS renders menu icons as templates and would eat the colour.
struct ColorSwatchPicker: View {
    let selected: PadColor
    let onPick: (PadColor) -> Void

    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Cor do pad")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(theme.ink)

            HStack(spacing: 8) {
                ForEach(PadColor.allCases, id: \.self) { color in
                    Button { onPick(color) } label: {
                        Circle()
                            .fill(color.color(scheme))
                            .frame(width: 26, height: 26)
                            .overlay(
                                Circle().stroke(theme.ink, lineWidth: color == selected ? 2 : 0)
                            )
                            .overlay(
                                Image(systemName: "checkmark")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(theme.bg)
                                    .opacity(color == selected ? 1 : 0)
                            )
                    }
                    .buttonStyle(.plain)
                    .help(color.label)
                    .accessibilityLabel(color.label)
                }
            }
        }
        .padding(14)
    }
}

#Preview("Seletor de cor") {
    ColorSwatchPicker(selected: .menta, onPick: { _ in })
        .environment(\.theme, .dark)
        .background(Theme.dark.surface)
}
