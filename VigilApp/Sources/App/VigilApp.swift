import SwiftUI

@main
struct VigilApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            HomeView(model: model)
                .environment(\.locale, model.language.locale)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { model.flushPendingWrites() }
        }
        #if os(macOS)
        .defaultSize(width: 1180, height: 820)
        .commands { menuBar }
        #endif
    }

    #if os(macOS)
    /// Shortcuts always carry Command: the bare letters belong to the pads. Titles resolve
    /// through `model.t` because commands live on the Scene, where the environment locale
    /// never reaches.
    @CommandsBuilder
    private var menuBar: some Commands {
        CommandGroup(replacing: .appSettings) {
            Button(model.t("Configurações…")) { model.activeSheet = .settings }
                .keyboardShortcut(",")
        }

        CommandMenu(model.t("Instrumento")) {
            Menu(model.t("Sons de Pads")) {
                ForEach(model.catalog.padSoundList) { sound in
                    Button(model.t(dynamic: sound.name)) { model.selectPadSound(sound.id) }
                }
            }
            Menu(model.t("Drum Kits")) {
                ForEach(model.catalog.kits) { kit in
                    Button(kit.name) { model.selectKit(kit) }
                }
                if !model.userKits.kits.isEmpty {
                    Divider()
                    ForEach(model.userKits.kits) { kit in
                        Button(kit.name) { model.selectUserKit(kit) }
                    }
                }
            }
            Divider()
            Button(model.t("Salvar kit atual…")) { model.activeSheet = .saveKit }
        }

        CommandMenu(model.t("Sets")) {
            Button(model.t("Padrão")) { model.loadDefaultSet() }
            if !model.sets.sets.isEmpty {
                Divider()
                ForEach(model.sets.sets) { set in
                    Button(set.name) { model.loadSet(set) }
                }
            }
            Divider()
            Button(model.t("Salvar novo Set…")) { model.activeSheet = .saveSet }
                .keyboardShortcut("s")
            Button(model.t("Gerenciar Sets…")) { model.activeSheet = .manageSets }
        }

        CommandMenu(model.t("Sample Drum")) {
            Button(model.t("Importar Sample…")) { model.isImporting = true }
                .keyboardShortcut("i")
            Button(model.t("Gerenciar Samples…")) { model.activeSheet = .manageSamples }
        }

        CommandMenu("MIDI") {
            Button(model.t("Entradas, canal e MIDI Learn…")) { model.activeSheet = .midi }
                .keyboardShortcut("k")
        }
    }
    #endif
}
