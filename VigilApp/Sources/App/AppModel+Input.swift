import Foundation
import Observation

extension AppModel {

    func handleKey(_ character: Character) -> Bool {
        receive(.key(String(character).lowercased()), value: nil)
    }

    /// Learned bindings first. Unlearned input falls back the way a controller expects out of
    /// the box: channel 10 notes 36 to 43 hit the drum pads, other notes on the chosen channel
    /// play the tonal pad by pitch class, CC 64 is the sustain pedal and CC 120 or 123 stops
    /// every sound. With the pad unlatched a note plays only while its key or the pedal holds it.
    func handleMidi(_ event: MidiEvent) {
        if case .note(10, let number, let velocity) = event, learning == nil,
           midiConfig.target(for: .note(number)) == nil {
            if let pad = drums.pads[safe: Int(number) - 36] {
                trigger(pad, velocity: Self.velocityGain(velocity))
            }
            return
        }
        guard event.channel == midiConfig.channel else { return }
        switch event {
        case .note(_, let number, let velocity):
            if !settings.padLatch, learning == nil, let note = tonalTarget(forKey: number) {
                heldKeys[number] = note
                if tonal.activeNote != note { tonal.play(note) }
                return
            }
            if !receive(.note(number), value: nil, velocity: Self.velocityGain(velocity)) {
                toggleNote(Note.allCases[Int(number) % 12])
            }
        case .noteOff(_, let number):
            guard !settings.padLatch, learning == nil, heldKeys.removeValue(forKey: number) != nil else { return }
            releaseUnheldNote()
        case .control(_, let number, let value):
            guard !receive(.cc(number), value: Double(value) / 127) else { return }
            if number == 120 || number == 123 { panic() }
            if number == 64 { setSustain((value >= 64) != settings.sustainInverted) }
        }
    }

    /// The tonal note a key plays: its learned target, or its pitch class when unlearned.
    func tonalTarget(forKey number: UInt8) -> Note? {
        switch midiConfig.target(for: .note(number)) {
        case .tonal(let note): note
        case nil: Note.allCases[Int(number) % 12]
        default: nil
        }
    }

    func setSustain(_ down: Bool) {
        sustainDown = down
        if !down { releaseUnheldNote() }
    }

    /// Stops the pad once no key and no pedal holds its note. A latched pad ignores this.
    func releaseUnheldNote() {
        guard !settings.padLatch, !sustainDown, let active = tonal.activeNote,
              !heldKeys.values.contains(active) else { return }
        tonal.stop()
    }

    /// All Sound Off: the tonal pad and every drum voice. The metronome is a clock, not a sound.
    func panic() {
        tonal.stop()
        drums.stopAll()
    }

    /// Drum velocity curve: a soft hit sits louder than linear, which is how pads feel played.
    static func velocityGain(_ velocity: UInt8) -> Double {
        pow(Double(min(velocity, 127)) / 127, 0.7)
    }

    /// The same log mapping as the frequency sliders, so a knob and the slider agree.
    static func logScale(_ value: Double, to range: ClosedRange<Double>) -> Double {
        range.lowerBound * pow(range.upperBound / range.lowerBound, min(max(value, 0), 1))
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
        case .cutoff: if let value { settings.cutoff = Self.logScale(value, to: Settings.cutoffRange) }
        case .highpass: if let value { settings.highpass = Self.logScale(value, to: Settings.highpassRange) }
        case .padReverb: if let value { settings.padReverb = value }
        case .pulseDepth: if let value { settings.pulseDepth = value }
        case .drumVolume(let index):
            if let value, let pad = drums.pads[safe: index] { pad.volume = value }
        }
    }

    struct LearnRequest: Equatable {
        let target: MidiTarget
        let keyboard: Bool
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

    func setVoicing(_ pad: DrumPad, to voicing: PadVoicing) {
        pad.voicing = voicing
        savePads()
    }

    func setTrim(_ pad: DrumPad, to trim: ClosedRange<Double>) {
        pad.trim = PadTrim.clamp(trim)
        savePads()
    }

    func setReverbSend(_ pad: DrumPad, to value: Double) {
        pad.reverbSend = min(max(value, 0), 1)
        savePads()
    }

    func setVolume(_ pad: DrumPad, to value: Double) {
        pad.volume = value
        scheduleAutosave()
    }

}
