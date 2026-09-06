import SwiftUI
import UniformTypeIdentifiers

struct HomeView: View {
    @Environment(\.colorScheme) private var scheme
    @State private var model = AppModel()
    @State private var importing = false
    @State private var showingSettings = false
    @State private var savingKit = false
    @State private var savingSet = false
    @State private var managingSets = false
    @State private var managingSamples = false
    @State private var showingMidi = false

    private var isSheetOpen: Bool {
        showingSettings || showingMidi || savingKit || savingSet || managingSets || managingSamples
    }

    private let drumColumns = Array(
        repeating: GridItem(.flexible(), spacing: Metrics.padGap),
        count: 4
    )

    var body: some View {
        let theme = Theme.of(scheme)

        ZStack {
            theme.bg.ignoresSafeArea()

            VStack(spacing: Metrics.zoneGap) {
                header
                selectors
                HStack(alignment: .top, spacing: Metrics.zoneGap) {
                    tonalZone
                        .frame(width: 268)
                    drumZone
                }
                .frame(maxHeight: .infinity)
            }
            .padding(Metrics.zoneGap)

            if !isSheetOpen {
                ToastLayer(center: model.toasts).zIndex(1)
            }
        }
        .environment(\.theme, theme)
        .environment(\.locale, model.language.locale)
        .fileImporter(
            isPresented: $importing,
            allowedContentTypes: [.audio],
            allowsMultipleSelection: false
        ) { result in
            model.handleImport(result)
        }
        .task { model.start() }
        .preferredColorScheme(model.theme.colorScheme)
        .sheet(isPresented: $savingKit) {
            NamePrompt(
                title: "Salvar kit",
                placeholder: "Ex.: Meu Kit",
                onCancel: { savingKit = false },
                onConfirm: { name in
                    model.saveCurrentKit(named: name)
                    savingKit = false
                }
            )
            .environment(\.theme, theme)
            .environment(\.locale, model.language.locale)
            .toasts(model.toasts)
        }
        .sheet(isPresented: $savingSet) {
            NamePrompt(
                title: "Salvar Set",
                placeholder: "Ex.: Meu Set",
                onCancel: { savingSet = false },
                onConfirm: { name in
                    model.saveCurrentSet(named: name)
                    savingSet = false
                }
            )
            .environment(\.theme, theme)
            .environment(\.locale, model.language.locale)
            .toasts(model.toasts)
        }
        .sheet(isPresented: $managingSets) {
            ManageList(
                title: "Gerenciar Sets",
                items: model.sets.sets.map {
                    ManageItem(id: $0.id, name: $0.name, detail: $0.padSoundID)
                },
                emptyTitle: "Nenhum set salvo",
                emptyMessage: "Um set guarda o som do pad, o kit e os volumes. Salve o atual para voltar a ele depois.",
                onRename: { item, name in
                    if let set = model.sets.sets.first(where: { $0.id == item.id }) {
                        model.renameSet(set, to: name)
                    }
                },
                onDelete: { item in
                    if let set = model.sets.sets.first(where: { $0.id == item.id }) {
                        model.deleteSet(set)
                    }
                },
                onSelect: { item in
                    if let set = model.sets.sets.first(where: { $0.id == item.id }) {
                        model.loadSet(set)
                    }
                },
                onClose: { managingSets = false }
            )
            .environment(\.theme, theme)
            .environment(\.locale, model.language.locale)
            .toasts(model.toasts)
        }
        .sheet(isPresented: $managingSamples) {
            ManageList(
                title: "Gerenciar Samples",
                items: model.library.samples.map {
                    ManageItem(id: $0.id, name: $0.displayName, detail: $0.fileName)
                },
                emptyTitle: "Nenhum sample importado",
                emptyMessage: "Importe um áudio e ele fica disponível para qualquer pad.",
                onRename: { item, name in
                    if let sample = model.library.samples.first(where: { $0.id == item.id }) {
                        model.renameSample(sample, to: name)
                    }
                },
                onDelete: { item in
                    if let sample = model.library.samples.first(where: { $0.id == item.id }) {
                        model.delete(sample)
                    }
                },
                onSelect: nil,
                onClose: { managingSamples = false }
            )
            .environment(\.theme, theme)
            .environment(\.locale, model.language.locale)
            .toasts(model.toasts)
        }
        .sheet(isPresented: $showingMidi) {
            MidiView(model: model) { showingMidi = false }
                .environment(\.theme, theme)
            .environment(\.locale, model.language.locale)
            .toasts(model.toasts)
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView(
                model: model,
                onClose: { showingSettings = false },
                // A nested sheet would duplicate the toast layer.
                onOpenMidi: {
                    showingSettings = false
                    showingMidi = true
                }
            )
                .environment(\.theme, theme)
            .environment(\.locale, model.language.locale)
            .toasts(model.toasts)
        }
        // .onKeyPress only fires along the focus path, so the root has to be focusable.
        .focusable()
        .focusEffectDisabled()
        .onKeyPress(phases: .down) { press in
            // While a sheet is open the keyboard belongs to it, not to the pads.
            guard !isSheetOpen, let character = press.characters.first else { return .ignored }
            return model.handleKey(character) ? .handled : .ignored
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            MainMenu(
                padSounds: model.catalog.padSoundList,
                activeSoundID: model.tonal.soundID,
                kits: model.catalog.kits,
                userKits: model.userKits.kits,
                currentKit: model.currentKit,
                onSelectSound: { model.selectPadSound($0.id) },
                onSelectKit: { model.selectKit($0) },
                onSelectUserKit: { model.selectUserKit($0) },
                onSaveKit: { savingKit = true },
                onDeleteUserKit: { model.deleteUserKit($0) },
                onImport: { importing = true },
                currentSetName: model.currentSetName,
                sets: model.sets.sets,
                onSelectSet: { model.loadSet($0) },
                onDefaultSet: { model.loadDefaultSet() },
                onSaveSet: { savingSet = true },
                onManageSets: { managingSets = true },
                onManageSamples: { managingSamples = true }
            )
            Wordmark()
            Spacer()
            Button { model.settings.doubleTime.toggle() } label: {
                Text("2x")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(model.settings.doubleTime ? Theme.of(scheme).accent : Theme.of(scheme).inkMuted)
                    .frame(width: Metrics.minTarget, height: Metrics.minTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Dobra o clique do metrônomo")

            Button { model.metronome.toggle() } label: {
                Image(systemName: "metronome")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(model.metronome.isRunning ? Theme.of(scheme).accent : Theme.of(scheme).ink)
                    .frame(width: Metrics.minTarget, height: Metrics.minTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Metrônomo")

            Button { showingSettings = true } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Theme.of(scheme).ink)
                    .frame(width: Metrics.minTarget, height: Metrics.minTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Configurações")
        }
    }

    private var selectors: some View {
        VStack(spacing: 6) {
            StepperSelector(
                title: "Pad",
                value: model.padSoundName,
                onPrevious: { model.stepPadSound(-1) },
                onNext: { model.stepPadSound(1) }
            )
            StepperSelector(
                title: "Drum Kit",
                value: model.kitName,
                onPrevious: { model.stepKit(-1) },
                onNext: { model.stepKit(1) }
            )
        }
    }

    private var tonalZone: some View {
        VStack(alignment: .leading, spacing: Metrics.padGap) {
            ZoneLabel("Tons")
            TonalPadGrid(
                activeNote: model.tonal.activeNote,
                sharps: model.settings.sharps,
                major: model.settings.major,
                onToggle: { model.toggleNote($0) }
            )
            TransportPanel(
                activeNote: model.tonal.activeNote,
                sharps: model.settings.sharps,
                major: model.settings.major,
                onStopDrums: { model.drums.stopAll() }
            )
        }
    }

    private var drumZone: some View {
        VStack(alignment: .leading, spacing: Metrics.padGap) {
            ZoneLabel("Drums")
            ForEach(padRows, id: \.self) { row in
                HStack(spacing: Metrics.padGap) {
                    ForEach(row, id: \.self) { index in
                        if let pad = model.drums.pads[safe: index] { padCard(pad) }
                    }
                }
            }
            if model.drums.pads.allSatisfy({ !$0.isAssigned }) {
                emptyPads(Theme.of(scheme))
            }
        }
        .frame(maxHeight: .infinity)
    }

    private var padRows: [[Int]] { [[0, 1, 2, 3], [4, 5, 6, 7]] }

    private func padCard(_ pad: DrumPad) -> some View {
        DrumPadView(
            pad: pad,
            isPlaying: model.playingPadIDs.contains(pad.id),
            kits: model.catalog.kits,
            samples: model.library.samples,
            onTap: { model.trigger(pad) },
            onPickNative: { model.assign(pad, kit: $0, slotIndex: $1) },
            onPickSample: { model.assign(pad, sample: $0) },
            onColor: { model.setColor(pad, to: $0) },
            onClear: { model.clear(pad) },
            onVolume: { model.setVolume(pad, to: $0) }
        )
    }

    private func emptyPads(_ theme: Theme) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Nenhum som nos pads")
                .font(.system(size: 24, weight: .regular, design: .serif))
                .foregroundStyle(theme.ink)
            Text("Clique com o botão direito num pad para escolher um som de fábrica, ou importe o seu.")
                .font(.system(size: 15))
                .foregroundStyle(theme.inkMuted)
            Button("Importar sample") { importing = true }
                .buttonStyle(.plain)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(theme.accent)
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Metrics.zoneGap)
        .background(theme.surface, in: RoundedRectangle(cornerRadius: Metrics.padRadius))
    }
}

#Preview("Home — dark") {
    HomeView().frame(width: 1180, height: 820)
}

#Preview("Home — light") {
    HomeView().frame(width: 1180, height: 820).environment(\.colorScheme, .light)
}
