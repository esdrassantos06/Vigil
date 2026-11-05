import SwiftUI
import UniformTypeIdentifiers

struct HomeView: View {
    @Environment(\.colorScheme) private var scheme
    @Bindable var model: AppModel

    @State private var windowSize = CGSize(width: 1280, height: 820)

    /// From the window, never the content: measuring the content would let a wide layout keep
    /// itself wide.
    private var isNarrow: Bool { windowSize.width < 1180 }
    private var isPortrait: Bool { windowSize.height > windowSize.width }

    private var isSheetOpen: Bool { model.activeSheet != nil }

    var body: some View {
        GeometryReader { proxy in
            stage
                .frame(width: proxy.size.width, height: proxy.size.height)
                .onChange(of: proxy.size, initial: true) { _, size in windowSize = size }
        }
    }

    @ViewBuilder
    private var stage: some View {
        let theme = model.theme.resolve(scheme)

        ZStack {
            ThemeBackdrop()
            StageHaze(
                padColors: model.drums.pads.map { $0.isAssigned ? $0.color.color(scheme) : nil },
                isNoteSounding: model.tonal.activeNote != nil,
                isPortrait: isPortrait
            )

            VStack(spacing: 14) {
                HomeToolbar(model: model)
                StageStrip(model: model, isCompact: isNarrow)
                if isPortrait {
                    VStack(spacing: 16) {
                        tonalZone
                            .containerRelativeFrame(.vertical, count: 10, span: 3, spacing: 16)
                        drumZone
                    }
                } else {
                    HStack(alignment: .top, spacing: 16) {
                        tonalZone
                            .containerRelativeFrame(.horizontal, count: 12, span: 5, spacing: 16)
                        drumZone
                    }
                    .frame(maxHeight: .infinity)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
            .padding(.top, 12)


            if !isSheetOpen {
                ToastLayer(center: model.toasts).zIndex(1)
            }
        }
        #if os(macOS)
        .frame(minWidth: 960, minHeight: 680)
        #endif
        .environment(\.theme, theme)
        .environment(\.locale, model.language.locale)
        .fileImporter(
            isPresented: $model.isImporting,
            allowedContentTypes: [.audio],
            allowsMultipleSelection: false
        ) { result in
            model.handleImport(result)
        }
        .task { model.start() }
        .preferredColorScheme(model.theme.colorScheme)
        .sheet(item: $model.activeSheet) { sheet in
            sheetContent(sheet)
                .environment(\.theme, theme)
                .environment(\.locale, model.language.locale)
                .toasts(model.toasts)
        }
        // .onKeyPress only fires along the focus path, so the root has to be focusable.
        .focusable()
        .focusEffectDisabled()
        .onKeyPress(phases: [.down, .repeat, .up]) { press in
            // While a sheet is open the keyboard belongs to it, not to the pads.
            // A menu shortcut carries a modifier; without this guard Command-S would also
            // fire a pad.
            guard !isSheetOpen, press.modifiers.isEmpty,
                  let character = press.characters.first else { return .ignored }
            let handled = switch press.phase {
            case .up: model.handleKeyUp(character)
            case .repeat: model.handleKeyRepeat(character)
            default: model.handleKey(character)
            }
            return handled ? .handled : .ignored
        }
    }

    @ViewBuilder
    private func sheetContent(_ sheet: AppSheet) -> some View {
        switch sheet {
        case .saveKit:
            NamePrompt(
                title: "Salvar kit",
                placeholder: "Ex.: Meu Kit",
                onCancel: { model.activeSheet = nil },
                onConfirm: { name in
                    model.saveCurrentKit(named: name)
                    model.activeSheet = nil
                }
            )
        case .saveSet:
            NamePrompt(
                title: "Salvar Set",
                placeholder: "Ex.: Meu Set",
                onCancel: { model.activeSheet = nil },
                onConfirm: { name in
                    model.saveCurrentSet(named: name)
                    model.activeSheet = nil
                }
            )
        case .manageSets:
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
                onClose: { model.activeSheet = nil }
            )
        case .manageSamples:
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
                onClose: { model.activeSheet = nil }
            )
        case .midi:
            MidiView(model: model) { model.activeSheet = nil }
        case .settings:
            SettingsView(
                model: model,
                onClose: { model.activeSheet = nil },
                // A nested sheet would duplicate the toast layer.
                onOpenMidi: {
                    model.activeSheet = nil
                    model.activeSheet = .midi
                }
            )
        }
    }

    private var tonalZone: some View {
        VStack(spacing: Metrics.padGap) {
            TonalPadGrid(
                activeNote: model.tonal.activeNote,
                sharps: model.settings.sharps,
                major: model.settings.major,
                intensity: model.settings.padMaster,
                columns: isPortrait ? 6 : 4,
                keyHint: { model.midiConfig.keyHint(for: .tonal($0)) },
                onPress: { model.pressNote($0) },
                onRelease: { model.releaseNote($0) }
            )
            TonalFooter(latch: $model.settings.padLatch, crossfade: model.settings.crossfade)
        }
        .padding(16)
        .frame(maxHeight: .infinity)
        .glassPane(radius: Metrics.paneRadius)
    }

    private var drumZone: some View {
        VStack(alignment: .leading, spacing: Metrics.padGap) {
            ForEach(padRows, id: \.self) { row in
                HStack(spacing: Metrics.padGap) {
                    ForEach(row, id: \.self) { index in
                        if let pad = model.drums.pads[safe: index] {
                            padCard(pad).frame(minWidth: 0, maxWidth: .infinity)
                        }
                    }
                }
            }
            if model.drums.pads.allSatisfy({ !$0.isAssigned }) {
                emptyPads(model.theme.resolve(scheme))
            }
        }
        .frame(maxHeight: .infinity)
    }

    private var padRows: [[Int]] { [[0, 1, 2, 3], [4, 5, 6, 7]] }

    private func padCard(_ pad: DrumPad) -> some View {
        DrumPadView(
            pad: pad,
            keyHint: model.midiConfig.keyHint(for: .drum(pad.id)),
            kits: model.catalog.kits,
            samples: model.library.samples,
            onTap: { model.trigger(pad) },
            onPickNative: { model.assign(pad, kit: $0, slotIndex: $1) },
            onPickSample: { model.assign(pad, sample: $0) },
            onColor: { model.setColor(pad, to: $0) },
            onVoicing: { model.setVoicing(pad, to: $0) },
            onClear: { model.clear(pad) },
            onVolume: { model.setVolume(pad, to: $0) },
            onTrim: { model.setTrim(pad, to: $0) },
            onReverbSend: { model.setReverbSend(pad, to: $0) }
        )
    }

    private func emptyPads(_ theme: Theme) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Nenhum som nos pads")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(theme.ink)
            Text("Clique com o botão direito num pad para escolher um som de fábrica, ou importe o seu.")
                .font(.system(size: 15))
                .foregroundStyle(theme.inkMuted)
            Button("Importar sample") { model.isImporting = true }
                .buttonStyle(.plain)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(theme.accent)
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Metrics.zoneGap)
        .glassPane(radius: Metrics.panelRadius)
    }
}

#Preview("Home — dark") {
    HomeView(model: AppModel()).frame(width: 1180, height: 820)
}

#Preview("Home — light") {
    HomeView(model: AppModel()).frame(width: 1180, height: 820).environment(\.colorScheme, .light)
}
