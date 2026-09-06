import Foundation
import Observation

extension AppModel {

    struct PadState: Codable {
        let id: Int
        let source: PadSource
        let color: PadColor
        let volume: Double
        let voicing: PadVoicing

        init(id: Int, source: PadSource, color: PadColor, volume: Double, voicing: PadVoicing) {
            self.id = id
            self.source = source
            self.color = color
            self.volume = volume
            self.voicing = voicing
        }

        /// State written before the play mode existed loads as overlapping.
        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = try container.decode(Int.self, forKey: .id)
            source = try container.decode(PadSource.self, forKey: .source)
            color = try container.decode(PadColor.self, forKey: .color)
            volume = try container.decode(Double.self, forKey: .volume)
            voicing = try container.decodeIfPresent(PadVoicing.self, forKey: .voicing) ?? .poly
        }
    }

    func savePads() { scheduleAutosave() }

    /// Quitting within the debounce window would otherwise lose the change.
    func flushPendingWrites() {
        commitAutosave()
        settingsSaveTask?.cancel()
        settingsSaveTask = nil
        defaults.store(settings, forKey: settingsKey)
    }

    func scheduleAutosave() {
        guard !isLoading else { return }
        autosaveTask?.cancel()
        autosaveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            self?.commitAutosave()
        }
    }

    func commitAutosave() {
        autosaveTask?.cancel()
        autosaveTask = nil
        persistPads()
        syncActiveKit()
        syncActiveSet()
    }

    func syncActiveKit() {
        guard case .user(let id) = currentKit else { return }
        userKits.update(id: id, slots: currentSlots())
    }

    func syncActiveSet() {
        guard let id = currentSetID,
              var set = sets.sets.first(where: { $0.id == id }) else { return }
        set.padSoundID = tonal.soundID
        set.kit = currentKit
        set.settings = settings
        sets.update(set)
    }

    func persistPads() {
        let state = drums.pads.map {
            PadState(id: $0.id, source: $0.source, color: $0.color,
                     volume: $0.volume, voicing: $0.voicing)
        }
        defaults.store(state, forKey: padsKey)
        defaults.store(currentKit, forKey: kitKey)
    }

    @discardableResult
    func restorePads() -> Bool {
        guard let state = defaults.decoded([PadState].self, forKey: padsKey) else { return false }

        currentKit = defaults.decoded(KitRef.self, forKey: kitKey)

        var missing = 0
        for saved in state {
            guard let pad = drums.pads[safe: saved.id] else { continue }
            pad.color = saved.color
            pad.volume = saved.volume
            pad.voicing = saved.voicing
            if !apply(source: saved.source, to: pad) { missing += 1 }
        }

        if currentKit == nil, let inferred = inferredKitID() {
            currentKit = .factory(inferred)
            savePads()
        }

        if missing > 0 {
            toasts.info(t("\(missing) pad(s) sem som: o arquivo não foi encontrado."))
        }
        return true
    }

    func applySettings() {
        tonal.master = settings.padMaster
        tonal.pan = settings.padPan
        tonal.cutoff = settings.cutoff
        tonal.highpass = settings.highpass
        tonal.crossfade = settings.crossfade
        drums.master = settings.drumMaster
        drums.pan = settings.drumPan
        metronome.bpm = settings.bpm
        metronome.timeSignature = settings.timeSignature
        metronome.sound = settings.clickSound
        metronome.accentFirst = settings.accentFirst
        metronome.doubleTime = settings.doubleTime
        metronome.volume = settings.metronomeVolume
        metronome.pan = settings.metronomePan
    }

    func tapTempo() {
        metronome.tap()
        settings.bpm = metronome.bpm
    }

    /// Debounced: dragging a slider emits hundreds of changes, each one an encode.
    func saveSettings() {
        settingsSaveTask?.cancel()
        settingsSaveTask = Task { [settings, settingsKey] in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            defaults.store(settings, forKey: settingsKey)
        }
    }

    func restoreTheme() {
        if let raw = defaults.string(forKey: themeKey),
           let saved = AppTheme(rawValue: raw) {
            theme = saved
            return
        }
        guard let data = defaults.data(forKey: settingsKey),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let raw = json["theme"] as? String,
              let saved = AppTheme(rawValue: raw)
        else { return }
        theme = saved
    }

    func loadSettings() {
        if let decoded = defaults.decoded(Settings.self, forKey: settingsKey) {
            settings = decoded.clamped()
        }
        applySettings()
    }

    func inferredKitID() -> String? {
        let ids = drums.pads.compactMap { pad -> String? in
            if case .native(let kit, _) = pad.source { return kit }
            return nil
        }
        guard let first = ids.first, ids.count == drums.pads.count,
              ids.allSatisfy({ $0 == first }) else { return nil }
        return first
    }

    func flash(_ pad: DrumPad) {
        pad.isFlashing = true
        releaseTasks[pad.id]?.cancel()
        releaseTasks[pad.id] = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(120))
            guard !Task.isCancelled else { return }
            pad.isFlashing = false
            self?.releaseTasks[pad.id] = nil
        }
    }
}
