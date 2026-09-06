import SwiftUI

struct DrumPadView: View {
    let pad: DrumPad
    let kits: [FactoryKit]
    let samples: [Sample]
    let onTap: () -> Void
    let onPickNative: (FactoryKit, Int) -> Void
    let onPickSample: (Sample) -> Void
    let onColor: (PadColor) -> Void
    let onVoicing: (PadVoicing) -> Void
    let onClear: () -> Void
    let onVolume: (Double) -> Void

    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var scheme
    @State private var pickingColor = false

    var body: some View {
        VStack(spacing: 0) {
            Button(action: onTap) { face }
                .buttonStyle(.plain)
                .contextMenu { menu }
            if pad.isAssigned { volumeStrip }
        }
        .background(theme.surface2)
        .clipShape(RoundedRectangle(cornerRadius: Metrics.padRadius))
        .overlay(
            RoundedRectangle(cornerRadius: Metrics.padRadius)
                .stroke(padBorder, lineWidth: 1)
        )
        .popover(isPresented: $pickingColor, arrowEdge: .bottom) {
            ColorSwatchPicker(selected: pad.color) { color in
                onColor(color)
                pickingColor = false
            }
        }
        .accessibilityLabel(pad.name.map { "\(pad.label), \($0)" } ?? "\(pad.label), vazio")
    }

    private var face: some View {
        ZStack(alignment: .topLeading) {
            HStack(alignment: .top) {
                Text(pad.label)
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(1.0)
                    .foregroundStyle(theme.inkMuted)
                Spacer(minLength: 0)
                if pad.isFlashing {
                    Circle()
                        .fill(theme.accent)
                        .frame(width: 8, height: 8)
                        .padding(.top, 2)
                }
            }

            Group {
                if let name = pad.name {
                    Text(name)
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(theme.ink)
                } else {
                    Image(systemName: "plus")
                        .font(.system(size: 20, weight: .light))
                        .foregroundStyle(theme.inkMuted)
                }
            }
            .lineLimit(2)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 80, maxHeight: .infinity, alignment: .topLeading)
        .background(padBackground)
        .contentShape(Rectangle())
    }

    private var volumeStrip: some View {
        HStack(spacing: 8) {
            Slider(value: Binding(get: { pad.volume }, set: onVolume))
                .controlSize(.mini)
            Text("\(Int(pad.volume * 100))%")
                .font(.system(size: 10, weight: .medium).monospacedDigit())
                .foregroundStyle(theme.inkMuted)
                .frame(width: 30, alignment: .trailing)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var padBackground: Color {
        guard pad.isAssigned else { return theme.surface }
        return pad.color.color(scheme).opacity(pad.isFlashing ? 0.45 : 0.28)
    }

    private var padBorder: Color {
        guard pad.isAssigned else { return theme.line }
        return pad.color.color(scheme).opacity(pad.isFlashing ? 1 : 0.55)
    }

    @ViewBuilder
    private var menu: some View {
        Button("Cor do pad…") { pickingColor = true }

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
