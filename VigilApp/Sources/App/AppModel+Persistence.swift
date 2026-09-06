import Foundation
import Observation

extension AppModel {

    struct PadState: Codable {
        let id: Int
        let source: PadSource
        let color: PadColor
        let volume: Double
    }

    func savePads() { scheduleAutosave() }

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

    /// Factory kits are read only; edits stay in the unsaved marker.
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
            PadState(id: $0.id, source: $0.source, color: $0.color, volume: $0.volume)
        }
        guard let data = try? JSONEncoder().encode(state) else { return }
        defaults.set(data, forKey: padsKey)
        if let data = try? JSONEncoder().encode(currentKit) {
            defaults.set(data, forKey: kitKey)
        }
    }

    @discardableResult
    func restorePads() -> Bool {
        guard let data = defaults.data(forKey: padsKey),
              let state = try? JSONDecoder().decode([PadState].self, from: data)
        else { return false }

        if let data = defaults.data(forKey: kitKey) {
            currentKit = try? JSONDecoder().decode(KitRef?.self, from: data)
        }

        var missing = 0
        for saved in state {
            guard let pad = drums.pads[safe: saved.id] else { continue }
            pad.color = saved.color
            pad.volume = saved.volume

            switch saved.source {
            case .empty:
                continue
            case .custom(let sampleID):
                guard let sample = library.samples.first(where: { $0.id == sampleID }) else {
                    missing += 1
                    continue
                }
                try? drums.load(
                    url: library.url(for: sample),
                    into: pad,
                    name: sample.displayName,
                    source: saved.source
                )
            case .native(let kitID, let slotIndex):
                guard let kit = catalog.kit(id: kitID),
                      let slot = kit.slots[safe: slotIndex],
                      let url = catalog.url(for: slot.file) else {
                    missing += 1
                    continue
                }
                try? drums.load(url: url, into: pad, name: slot.name, source: saved.source)
            }
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
            guard !Task.isCancelled, let data = try? JSONEncoder().encode(settings) else { return }
            defaults.set(data, forKey: settingsKey)
        }
    }

    func restoreTheme() {
        if let raw = defaults.string(forKey: themeKey),
           let saved = ThemePreference(rawValue: raw) {
            theme = saved
            return
        }
        guard let data = defaults.data(forKey: settingsKey),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let raw = json["theme"] as? String,
              let saved = ThemePreference(rawValue: raw)
        else { return }
        theme = saved
    }

    func loadSettings() {
        if let data = defaults.data(forKey: settingsKey),
           let decoded = try? JSONDecoder().decode(Settings.self, from: data) {
            settings = decoded
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
        playingPadIDs.insert(pad.id)
        releaseTasks[pad.id]?.cancel()
        releaseTasks[pad.id] = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(120))
            guard !Task.isCancelled else { return }
            self?.playingPadIDs.remove(pad.id)
            self?.releaseTasks[pad.id] = nil
        }
    }
}
