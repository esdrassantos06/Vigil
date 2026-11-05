import SwiftUI

/// The row above the stage strip: the main menu, the active set, the pad sound and drum kit
/// steppers, the MIDI input, and settings.
struct HomeToolbar: View {
    @Bindable var model: AppModel

    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(spacing: 10) {
            mainMenu
            Button { model.activeSheet = .manageSets } label: {
                PillText(title: "Set", value: model.currentSetName ?? model.t("Padrão"))
            }
            .glassButton()
            .help("Gerenciar Sets…")
            StepperPill(title: "Pad", value: model.padSoundName,
                        onPrevious: { model.stepPadSound(-1) }, onNext: { model.stepPadSound(1) })
            StepperPill(title: "Kit", value: model.kitName,
                        onPrevious: { model.stepKit(-1) }, onNext: { model.stepKit(1) })
            Spacer(minLength: 10)
            midiStatus
            Button { model.activeSheet = .settings } label: {
                Image(systemName: "gearshape")
            }
            .glassButton(shape: .circle)
            .help("Configurações")
            .accessibilityLabel("Configurações")
        }
        .controlSize(.large)
    }

    private var mainMenu: some View {
        MainMenu(
            padSounds: model.catalog.padSoundList,
            activeSoundID: model.tonal.soundID,
            kits: model.catalog.kits,
            userKits: model.userKits.kits,
            currentKit: model.currentKit,
            onSelectSound: { model.selectPadSound($0.id) },
            onSelectKit: { model.selectKit($0) },
            onSelectUserKit: { model.selectUserKit($0) },
            onSaveKit: { model.activeSheet = .saveKit },
            onDeleteUserKit: { model.deleteUserKit($0) },
            onImport: { model.isImporting = true },
            currentSetName: model.currentSetName,
            sets: model.sets.sets,
            onSelectSet: { model.loadSet($0) },
            onDefaultSet: { model.loadDefaultSet() },
            onSaveSet: { model.activeSheet = .saveSet },
            onManageSets: { model.activeSheet = .manageSets },
            onManageSamples: { model.activeSheet = .manageSamples }
        )
    }

    private var midiStatus: some View {
        let source = model.midi.sources.first?.name
        return Button { model.activeSheet = .midi } label: {
            HStack(spacing: 8) {
                Circle()
                    .fill(source == nil ? theme.line : PadColor.menta.color(scheme))
                    .frame(width: 7, height: 7)
                if let source {
                    Text(verbatim: source).lineLimit(1)
                    Text("· canal \(model.midiConfig.channel)").foregroundStyle(theme.inkMuted)
                } else {
                    Text("Sem MIDI").foregroundStyle(theme.inkMuted)
                }
            }
        }
        .glassButton()
        .help("Entradas, canal e MIDI Learn…")
    }
}

/// Caps title and value inside a toolbar pill.
private struct PillText: View {
    let title: LocalizedStringKey
    let value: String

    @Environment(\.theme) private var theme

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.system(size: 10.5, weight: .semibold))
                .textCase(.uppercase)
                .tracking(1.1)
                .foregroundStyle(theme.inkMuted)
            Text(verbatim: value)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(theme.ink)
                .lineLimit(1)
        }
    }
}

/// Previous and next around a value, as one glass capsule.
struct StepperPill: View {
    let title: LocalizedStringKey
    let value: String
    let onPrevious: () -> Void
    let onNext: () -> Void

    @Environment(\.theme) private var theme

    var body: some View {
        HStack(spacing: 0) {
            arrow("chevron.left", label: "Voltar", action: onPrevious)
            PillText(title: title, value: value)
                .frame(minWidth: 60, maxWidth: 220)
            arrow("chevron.right", label: "Avançar", action: onNext)
        }
        .frame(minHeight: Metrics.minTarget)
        .background { Color.clear.frame(height: Metrics.controlHeight).glassPane(Capsule()) }
    }

    private func arrow(_ symbol: String, label: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(theme.inkMuted)
                .frame(width: 36, height: Metrics.minTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}
