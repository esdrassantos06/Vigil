import Foundation
import Observation

/// Owns the audio graph and the stores. The UI talks to this, never to AVFoundation.
///
/// Split into per-topic extensions (`AppModel+*.swift`). `private` is file scoped, so
/// anything they share is internal to the module.
@MainActor
@Observable
final class AppModel {
    let toasts = ToastCenter()
    let library: SampleLibrary
    let catalog = FactoryCatalog()
    let userKits: KitStore
    let sets: SetStore
    let drums: DrumEngine
    let tonal: TonalPadEngine
    let metronome: MetronomeEngine
    let midi = MidiEngine()
    let midiConfig: MidiConfig

    var theme: ThemePreference = .system {
        didSet {
            guard theme != oldValue else { return }
            defaults.set(theme.rawValue, forKey: themeKey)
        }
    }

    var language: Language = .pt {
        didSet {
            guard language != oldValue else { return }
            defaults.set(language.rawValue, forKey: languageKey)
        }
    }

    /// Views read the environment locale; the model builds Strings and needs the bundle.
    /// - Parameter key: localization key, extracted into the string catalogue.
    /// - Returns: the string in the selected language.
    func t(_ key: String.LocalizationValue) -> String {
        String(localized: key, bundle: language.bundle, locale: language.locale)
    }

    func t(dynamic key: String) -> String {
        NSLocalizedString(key, bundle: language.bundle, value: key, comment: "")
    }

    func phrase(_ binding: MidiBinding) -> String {
        switch binding {
        case .key(let character): t("a tecla \(character.uppercased())")
        case .note(let number): t("a nota \(Int(number))")
        case .cc(let number): t("o CC \(Int(number))")
        }
    }

    func message(for error: Error) -> String {
        (error as? any VigilError).map { t($0.messageKey) } ?? error.localizedDescription
    }

    var learning: LearnRequest?

    var settings = Settings() {
        didSet {
            guard settings != oldValue else { return }
            applySettings()
            saveSettings()
            scheduleAutosave()
        }
    }
    var currentKit: KitRef?
    var currentSetID: UUID?

    var currentSetName: String? {
        currentSetID.flatMap { id in sets.sets.first { $0.id == id }?.name }
    }

    var kitName: String {
        let base: String
        switch currentKit {
        case .factory(let id): base = catalog.kit(id: id)?.name ?? "—"
        case .user(let id): base = userKits.kit(id: id)?.name ?? "—"
        case nil: return "—"
        }
        return isKitModified ? "\(base) •" : base
    }

    var isKitModified: Bool {
        guard let reference = referenceSlots() else { return false }
        return currentSlots() != reference
    }

    func currentSlots() -> [StoredSlot] {
        drums.pads.map { StoredSlot(source: $0.source, color: $0.color, volume: $0.volume) }
    }

    func referenceSlots() -> [StoredSlot]? {
        switch currentKit {
        case .factory(let id):
            guard let kit = catalog.kit(id: id) else { return nil }
            return kit.slots.enumerated().map { index, _ in
                StoredSlot(
                    source: .native(kit: id, slot: index),
                    color: PadColor.allCases[index % PadColor.allCases.count],
                    volume: 1.0
                )
            }
        case .user(let id):
            return userKits.kit(id: id)?.slots
        case nil:
            return nil
        }
    }

    var playingPadIDs: Set<Int> = []

    @ObservationIgnored let graph = AudioGraph()
    @ObservationIgnored var releaseTasks: [Int: Task<Void, Never>] = [:]
    @ObservationIgnored var settingsSaveTask: Task<Void, Never>?
    @ObservationIgnored var autosaveTask: Task<Void, Never>?
    /// While a set is loading nothing is written back.
    @ObservationIgnored var isLoading = false
    @ObservationIgnored let defaults: UserDefaults
    @ObservationIgnored let padsKey = "padState"
    @ObservationIgnored let kitKey = "kitID"
    @ObservationIgnored let settingsKey = "settings"
    @ObservationIgnored let languageKey = "language"
    @ObservationIgnored let themeKey = "theme"
    @ObservationIgnored let defaultKitID = "DrumKit1"

    /// - Parameter defaults: injected so tests never touch the real preferences.
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        library = SampleLibrary(defaults: defaults)
        userKits = KitStore(defaults: defaults)
        sets = SetStore(defaults: defaults)
        midiConfig = MidiConfig(defaults: defaults)
        drums = DrumEngine(graph: graph)
        tonal = TonalPadEngine(graph: graph, catalog: catalog)
        metronome = MetronomeEngine(graph: graph, catalog: catalog)
    }

    var padSoundName: String {
        t(dynamic: catalog.padSound(id: tonal.soundID)?.name ?? tonal.soundID)
    }

    func toggleNote(_ note: Note) { tonal.toggle(note) }

    func selectKit(_ kit: FactoryKit) {
        for (index, pad) in drums.pads.enumerated() {
            guard let slot = kit.slots[safe: index], let url = catalog.url(for: slot.file) else { continue }
            try? drums.load(url: url, into: pad, name: slot.name, source: .native(kit: kit.id, slot: index))
        }
        currentKit = .factory(kit.id)
        savePads()
        toasts.success(t("Kit \(kit.name) carregado."))
    }

    func stepKit(_ delta: Int) {
        let kits = allKits
        guard !kits.isEmpty else { return }
        commitAutosave()
        let current = kits.firstIndex { $0 == currentKit } ?? -1
        let next = (current + delta + kits.count) % kits.count
        apply(kits[next])
    }

    func start() {
        if let raw = defaults.string(forKey: languageKey),
           let saved = Language(rawValue: raw) {
            language = saved
        }
        restoreTheme()
        loadSettings()
        do {
            try graph.start()
        } catch {
            toasts.error(t("Não foi possível iniciar o áudio."))
        }
        startMidi()

        if !restorePads() {
            loadDefaultKit()
        }
    }

    func startMidi() {
        midi.onEvent = { [weak self] event in self?.handleMidi(event) }
        midi.onSourcesChanged = { [weak self] added, removed in
            guard let self else { return }
            for name in added { toasts.info(t("\(name) conectado.")) }
            for name in removed { toasts.info(t("\(name) desconectado.")) }
        }
        midi.disabled = midiConfig.disabledInputs
        do {
            try midi.start()
        } catch {
            toasts.error(message(for: error))
        }
    }

    func loadDefaultKit() {
        guard let kit = catalog.kit(id: defaultKitID) ?? catalog.kits.first else { return }
        for (index, pad) in drums.pads.enumerated() {
            guard let slot = kit.slots[safe: index], let url = catalog.url(for: slot.file) else { continue }
            try? drums.load(url: url, into: pad, name: slot.name, source: .native(kit: kit.id, slot: index))
        }
        currentKit = .factory(kit.id)
        savePads()
    }

    func trigger(_ pad: DrumPad, velocity: Double = 1) {
        guard pad.isAssigned else { return }
        drums.trigger(pad, velocity: velocity)
        flash(pad)
    }

}

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
