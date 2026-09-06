import Foundation
import Observation

extension AppModel {

    func handleKey(_ character: Character) -> Bool {
        receive(.key(String(character).lowercased()), value: nil)
    }

    func handleMidi(_ event: MidiEvent) {
        guard event.channel == midiConfig.channel else { return }
        switch event {
        case .note(_, let number, let velocity):
            _ = receive(.note(number), value: nil, velocity: Double(velocity) / 127)
        case .control(_, let number, let value):
            _ = receive(.cc(number), value: Double(value) / 127)
        }
    }

    @discardableResult
    func receive(_ binding: MidiBinding, value: Double?, velocity: Double = 1) -> Bool {
        if let request = learning {
            // The two slots are independent: learning a key ignores MIDI events.
            guard request.keyboard == binding.isKeyboard else { return false }
            let previousOwner = midiConfig.target(for: binding)
            midiConfig.set(binding, for: request.target)
            learning = nil
            if let previousOwner, previousOwner != request.target {
                toasts.info(t("\(t(dynamic: request.target.label)) recebeu \(phrase(binding)), que era de \(t(dynamic: previousOwner.label))."))
            } else {
                toasts.success(t("\(t(dynamic: request.target.label)) recebeu \(phrase(binding))."))
            }
            return true
        }
        guard let target = midiConfig.target(for: binding) else { return false }
        perform(target, value: value, velocity: velocity)
        return true
    }

    func perform(_ target: MidiTarget, value: Double?, velocity: Double = 1) {
        // A CC below halfway does not fire, so releasing a button will not trigger twice.
        let fired = value.map { $0 >= 0.5 } ?? true
        switch target {
        case .tonal(let note): if fired { toggleNote(note) }
        case .drum(let index):
            if fired, let pad = drums.pads[safe: index] { trigger(pad, velocity: velocity) }
        case .stop: if fired { drums.stopAll() }
        case .metronomeToggle: if fired { metronome.toggle() }
        case .tapTempo: if fired { tapTempo() }
        case .padMaster: if let value { settings.padMaster = value }
        case .drumMaster: if let value { settings.drumMaster = value }
        case .metronomeVolume: if let value { settings.metronomeVolume = value }
        case .cutoff: if let value { settings.cutoff = Self.scale(value, to: Settings.cutoffRange) }
        case .highpass: if let value { settings.highpass = Self.scale(value, to: Settings.highpassRange) }
        case .drumVolume(let index):
            if let value, let pad = drums.pads[safe: index] { pad.volume = value }
        }
    }

    struct LearnRequest: Equatable {
        let target: MidiTarget
        let keyboard: Bool
    }

    static func scale(_ value: Double, to range: ClosedRange<Double>) -> Double {
        range.lowerBound + value * (range.upperBound - range.lowerBound)
    }

    func startLearning(_ target: MidiTarget, keyboard: Bool) {
        learning = LearnRequest(target: target, keyboard: keyboard)
        toasts.info(keyboard
                    ? t("Aperte a tecla que vai controlar \(t(dynamic: target.label)).")
                    : t("Toque a nota ou mova o CC que vai controlar \(t(dynamic: target.label))."))
    }

    func setMidiInput(_ source: MidiSource, enabled: Bool) {
        if enabled {
            midiConfig.disabledInputs.remove(source.name)
        } else {
            midiConfig.disabledInputs.insert(source.name)
        }
        midi.disabled = midiConfig.disabledInputs
    }

    func stepPadSound(_ delta: Int) {
        let sounds = catalog.padSoundList
        guard !sounds.isEmpty else { return }
        let current = sounds.firstIndex { $0.id == tonal.soundID } ?? 0
        let next = (current + delta + sounds.count) % sounds.count
        selectPadSound(sounds[next].id)
    }

    func selectPadSound(_ id: String) {
        tonal.selectSound(id)
        scheduleAutosave()
    }

    func setVolume(_ pad: DrumPad, to value: Double) {
        pad.volume = value
        scheduleAutosave()
    }

}
