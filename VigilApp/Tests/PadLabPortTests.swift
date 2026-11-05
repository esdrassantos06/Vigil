import AVFoundation
import Foundation
import Testing
@testable import Vigil

/// Settings written by an older build must keep loading: a set whose JSON fails to decode
/// is dropped, and the next save overwrites it.
@Suite("Settings migration")
struct SettingsMigrationTests {

    @Test("Settings saved before reverb and pulse existed still decode, keeping their values")
    func oldSettingsDecode() throws {
        let old = #"{"padMaster":0.5,"padPan":0,"cutoff":3000,"highpass":40,"crossfade":2,"drumMaster":1,"drumPan":0,"sharps":false,"major":true,"bpm":90,"timeSignature":"6/8","clickSound":"logic","accentFirst":true,"doubleTime":false,"metronomeVolume":0.8,"metronomePan":0}"#
        let decoded = try JSONDecoder().decode(Settings.self, from: Data(old.utf8))

        #expect(decoded.padMaster == 0.5)
        #expect(decoded.bpm == 90)
        #expect(decoded.timeSignature == .sixEight)
        #expect(decoded.sharps == false)
        #expect(decoded.padReverb == 0)
        #expect(decoded.pulse == nil)
        #expect(decoded.pulseRate == .eighth)
    }

    @Test("A set saved before reverb and pulse existed still loads")
    func oldSetDecodes() throws {
        let old = #"[{"id":"5C1A0E66-7D2C-4C9E-9C5E-3B5C4F1E2A10","name":"Domingo","padSoundID":"Shimmer","settings":{"padMaster":0.8,"bpm":72}}]"#
        let sets = try JSONDecoder().decode([VigilSet].self, from: Data(old.utf8))
        #expect(sets.first?.name == "Domingo")
        #expect(sets.first?.settings.bpm == 72)
        #expect(sets.first?.settings.cutoff == Settings().cutoff)
    }

    @Test("New fields survive a round trip")
    func roundTrip() throws {
        var settings = Settings()
        settings.padReverb = 0.4
        settings.pulse = .gate
        settings.pulseRate = .sixteenth
        settings.pulseDepth = 0.7
        let data = try JSONEncoder().encode(settings)
        #expect(try JSONDecoder().decode(Settings.self, from: data) == settings)
    }
}

@Suite("Pulse shapes")
struct PulseShapeTests {

    @Test("Each shape follows its curve, and depth blends it with unity")
    func shapes() {
        #expect(PulseShape.gate.gain(phase: 0.2, depth: 1) == 1)
        #expect(abs(PulseShape.gate.gain(phase: 0.7, depth: 0.6) - 0.4) < 1e-9)
        #expect(abs(PulseShape.smooth.gain(phase: 0, depth: 1)) < 1e-9)
        #expect(abs(PulseShape.smooth.gain(phase: 0.5, depth: 1) - 1) < 1e-9)
        #expect(abs(PulseShape.pump.gain(phase: 0.5, depth: 1) - pow(0.5, 0.42)) < 1e-9)
        #expect(PulseShape.pump.gain(phase: 0, depth: 0) == 1)
    }

    @Test("Rates count cycles per beat")
    func rates() {
        #expect(PulseRate.quarter.cyclesPerBeat == 1)
        #expect(PulseRate.eighth.cyclesPerBeat == 2)
        #expect(PulseRate.eighthTriplet.cyclesPerBeat == 3)
        #expect(PulseRate.sixteenth.cyclesPerBeat == 4)
    }
}

@Suite("Pad trim")
struct PadTrimTests {

    @Test("Trim maps to frames, never empty and never past the end")
    func frames() {
        #expect(PadTrim.frames(0...1, of: 1000) == 0..<1000)
        #expect(PadTrim.frames(0.25...0.5, of: 1000) == 250..<500)
        #expect(PadTrim.frames(0.99...1, of: 1000) == 980..<1000, "start caps at 98%")
        #expect(PadTrim.frames(0.5...0.505, of: 1000) == 500..<520, "the window is at least 2%")
        #expect(PadTrim.frames(0...1, of: 0) == 0..<0)
    }
}

/// MIDI behaviour carried over from the pad lab: the drum velocity curve, log-scaled filter
/// CCs and the standard panic messages.
@MainActor
@Suite("Pad lab MIDI", .serialized)
struct PadLabMidiTests {

    private func model() -> AppModel {
        let id = UUID().uuidString
        let app = AppModel(defaults: UserDefaults(suiteName: "vigil.tests.\(id)")!,
                           samplesDirectory: FileManager.default.temporaryDirectory
                               .appendingPathComponent("vigil-tests/\(id)", isDirectory: true))
        app.start()
        return app
    }

    @Test("A soft hit is louder than linear, so playing feels natural")
    func velocityCurve() throws {
        let app = model()
        app.midiConfig.set(.note(60), for: .drum(0))
        let pad = try #require(app.drums.pads.first)

        app.midi.onEvent?(.note(channel: 1, number: 60, velocity: 64))
        let expected = pow(64.0 / 127, 0.7) * pad.volume * app.settings.drumMaster
        #expect(abs(Double(pad.voices[0].volume) - expected) < 0.001)
    }

    @Test("Cutoff and high-pass CCs travel the range on the same log scale as the slider")
    func logScaledFilters() {
        let app = model()
        app.midiConfig.set(.cc(74), for: .cutoff)
        app.midiConfig.set(.cc(75), for: .highpass)

        app.midi.onEvent?(.control(channel: 1, number: 74, value: 64))
        let range = Settings.cutoffRange
        let expected = range.lowerBound * pow(range.upperBound / range.lowerBound, 64.0 / 127)
        #expect(abs(app.settings.cutoff - expected) < 1)

        app.midi.onEvent?(.control(channel: 1, number: 75, value: 0))
        #expect(abs(app.settings.highpass - Settings.highpassRange.lowerBound) < 0.01)
        app.midi.onEvent?(.control(channel: 1, number: 75, value: 127))
        #expect(abs(app.settings.highpass - Settings.highpassRange.upperBound) < 0.01)
    }

    @Test("All Sound Off and All Notes Off stop the tonal pad")
    func panicStopsPad() {
        for number: UInt8 in [120, 123] {
            let app = model()
            app.toggleNote(.C)
            #expect(app.tonal.activeNote == .C)
            app.midi.onEvent?(.control(channel: 1, number: number, value: 0))
            #expect(app.tonal.activeNote == nil, "CC \(number) left the pad sounding")
        }
    }

    @Test("A learned CC 123 does its own job instead of the panic")
    func learnedPanicCCWins() {
        let app = model()
        app.midiConfig.set(.cc(123), for: .padMaster)
        app.toggleNote(.C)
        app.midi.onEvent?(.control(channel: 1, number: 123, value: 127))
        #expect(app.tonal.activeNote == .C)
        #expect(abs(app.settings.padMaster - 1) < 0.01)
    }

    @Test("The default mapping plays C to B from notes 60 to 71, and other notes play nothing")
    func defaultNotesPlayPad() {
        let app = model()
        app.midi.onEvent?(.note(channel: 1, number: 62, velocity: 100))
        #expect(app.tonal.activeNote == .D)
        app.midi.onEvent?(.note(channel: 1, number: 74, velocity: 100))
        #expect(app.tonal.activeNote == .D, "a note outside the mapping does nothing")
    }

    @Test("Default drum notes 36 to 43 hit the pads on the chosen channel and on channel 10")
    func defaultDrumNotes() {
        let app = model()
        app.midi.onEvent?(.note(channel: 10, number: 38, velocity: 127))
        #expect(app.drums.pads[2].isFlashing)
        app.midi.onEvent?(.note(channel: 1, number: 39, velocity: 127))
        #expect(app.drums.pads[3].isFlashing)
        app.midi.onEvent?(.note(channel: 10, number: 62, velocity: 127))
        #expect(app.tonal.activeNote == nil, "channel 10 only reaches drum targets")
    }

    @Test("A learned note takes the note away from its default owner")
    func learnedNoteWins() {
        let app = model()
        app.midiConfig.set(.note(62), for: .drum(0))
        app.midi.onEvent?(.note(channel: 1, number: 62, velocity: 100))
        #expect(app.tonal.activeNote == nil)
        #expect(app.drums.pads[0].isFlashing)
    }

    @Test("Other channels are ignored")
    func fallbackRespectsChannel() {
        let app = model()
        app.midi.onEvent?(.note(channel: 3, number: 62, velocity: 100))
        #expect(app.tonal.activeNote == nil)
    }

    @Test("Reverb and pulse depth can be learned")
    func newTargets() {
        let app = model()
        app.midiConfig.set(.cc(91), for: .padReverb)
        app.midiConfig.set(.cc(92), for: .pulseDepth)
        app.midi.onEvent?(.control(channel: 1, number: 91, value: 127))
        app.midi.onEvent?(.control(channel: 1, number: 92, value: 0))
        #expect(abs(app.settings.padReverb - 1) < 0.01)
        #expect(abs(app.settings.pulseDepth) < 0.01)
        #expect(MidiTarget.all.contains(.padReverb))
        #expect(MidiTarget.all.contains(.pulseDepth))
    }
}

@MainActor
@Suite("Pad trim on the model", .serialized)
struct PadTrimModelTests {

    private func sandbox() -> (UserDefaults, URL) {
        let id = UUID().uuidString
        return (UserDefaults(suiteName: "vigil.tests.\(id)")!,
                FileManager.default.temporaryDirectory.appendingPathComponent("vigil-tests/\(id)", isDirectory: true))
    }

    @Test("Trimming shortens what a hit plays")
    func trimShortensBuffer() throws {
        let (defaults, directory) = sandbox()
        let app = AppModel(defaults: defaults, samplesDirectory: directory)
        app.start()
        let pad = try #require(app.drums.pads.first)
        let full = try #require(pad.playBuffer?.frameLength)

        app.setTrim(pad, to: 0.25...0.75)
        let trimmed = try #require(pad.playBuffer?.frameLength)
        #expect(abs(Double(trimmed) - Double(full) / 2) <= 2)
        #expect(app.isKitModified, "a trimmed factory kit counts as edited")
    }

    @Test("Trim is saved with the pads and comes back on the next run")
    func trimPersists() throws {
        let (defaults, directory) = sandbox()
        let first = AppModel(defaults: defaults, samplesDirectory: directory)
        first.start()
        first.setTrim(first.drums.pads[2], to: 0.1...0.6)
        first.flushPendingWrites()

        let second = AppModel(defaults: defaults, samplesDirectory: directory)
        second.start()
        #expect(second.drums.pads[2].trim == 0.1...0.6)
        #expect(second.drums.pads[0].trim == 0...1)
    }

    @Test("Loading another sound resets the trim")
    func newSoundResetsTrim() throws {
        let (defaults, directory) = sandbox()
        let app = AppModel(defaults: defaults, samplesDirectory: directory)
        app.start()
        let pad = app.drums.pads[0]
        app.setTrim(pad, to: 0.3...0.4)
        let kit = try #require(app.catalog.kits.first { $0.id != "DrumKit1" })
        app.selectKit(kit)
        #expect(pad.trim == 0...1)
    }
}

/// Reverb and pulse measured on the rendered signal.
@MainActor
@Suite("Pad lab audio", .serialized)
struct PadLabAudioTests {

    private func render(seconds: Double = 2, configure: (TonalPadEngine) -> Void) async throws -> (samples: [Float], rate: Double) {
        let graph = AudioGraph(preparesImmediately: false)
        let tonal = TonalPadEngine(graph: graph, catalog: FactoryCatalog())
        tonal.crossfade = 0.05
        tonal.master = 1
        tonal.selectSound("Default")
        configure(tonal)
        let captured = try await OfflineRender.capture(
            graph, seconds: seconds, settle: .milliseconds(200),
            prepare: { tonal.toggle(.C) }, pump: {}
        )
        return (captured.samples, captured.sampleRate)
    }

    @Test("Reverb changes the sound, and at zero it is out of the way")
    func reverbAltersSignal() async throws {
        let dry = try await render { $0.reverb = 0 }.samples
        let untouched = try await render { _ in }.samples
        let wet = try await render { $0.reverb = 1 }.samples

        #expect(OfflineRender.rms(dry) > 0.001, "the pad rendered silence")
        #expect(shapeDifference(dry, untouched) < 0.01, "reverb at zero still colours the pad")
        #expect(shapeDifference(dry, wet) > 0.2, "reverb at full did not change the pad")
    }

    /// Level independent: the crossfade ramp is a `Task`, and under a busy main actor it can
    /// still be partway when the render starts, which scales the whole take.
    private func shapeDifference(_ a: [Float], _ b: [Float]) -> Float {
        let scaleA = max(OfflineRender.rms(a), 1e-9), scaleB = max(OfflineRender.rms(b), 1e-9)
        return OfflineRender.rms(zip(a, b).map { $0 / scaleA - $1 / scaleB })
    }

    @Test("A gate pulse at 120 BPM opens on the first half of each beat and closes on the second")
    func gatePulseFollowsTempo() async throws {
        let (samples, rate) = try await render(seconds: 2.1) { $0.setPulse(.gate, rate: .quarter, depth: 1, bpm: 120) }
        let beat = Int(0.5 * rate)
        var open: [Float] = [], closed: [Float] = []
        for start in stride(from: beat, to: beat * 4, by: beat) {
            let margin = Int(0.02 * rate)
            open += samples[(start + margin)..<(start + beat / 2 - margin)]
            closed += samples[(start + beat / 2 + margin)..<(start + beat - margin)]
        }
        let openLevel = OfflineRender.rms(open)
        #expect(openLevel > 0.001, "the pad rendered silence")
        #expect(OfflineRender.rms(closed) < openLevel * 0.05,
                "closed half \(OfflineRender.rms(closed)) against open half \(openLevel)")
    }

    @Test("With the pulse off the level stays flat")
    func noPulseIsFlat() async throws {
        let (samples, rate) = try await render(seconds: 2.1) { $0.setPulse(nil, rate: .quarter, depth: 1, bpm: 120) }
        let beat = Int(0.5 * rate)
        let first = OfflineRender.rms(Array(samples[beat..<(beat + beat / 2)]))
        let second = OfflineRender.rms(Array(samples[(beat + beat / 2)..<(beat * 2)]))
        #expect(second > first * 0.5)
    }
}

@Suite("Pad lab strings")
struct PadLabStringTests {
    @Test("The new controls translate")
    func translate() {
        let english = { (key: String.LocalizationValue) in
            String(localized: key, bundle: Language.en.bundle, locale: Language.en.locale)
        }
        #expect(english("Recortar…") == "Trim…")
        #expect(english("Profundidade") == "Depth")
        #expect(english("Desligado") == "Off")
        #expect(english(String.LocalizationValue(MidiTarget.pulseDepth.label)) == "Pulse (Pad)")
        #expect(english("Camadas") == "Layers")
        #expect(english("Para o pad") == "Stops the pad")
        #expect(english(String.LocalizationValue(DrumReverb.largeHall.label)) == "Large hall")
    }
}

@Suite("Pad lab settings, second pass")
struct PadLabSettingsTests {
    @Test("Settings saved before the second pass load with neutral values")
    func neutralDefaults() throws {
        let decoded = try JSONDecoder().decode(Settings.self, from: Data(#"{"bpm":100}"#.utf8))
        #expect(decoded.bpm == 100)
        #expect(decoded.padLow == 0 && decoded.padMid == 0 && decoded.padHigh == 0)
        #expect(decoded.padCompressor == false)
        #expect(decoded.drumHighpass == Settings.highpassRange.lowerBound)
        #expect(decoded.drumCutoff == Settings.drumCutoffRange.upperBound)
        #expect(decoded.outputDelay == 0)
        #expect(decoded.padLatch == true)
        #expect(decoded.sustainInverted == false)
        #expect(decoded.padMainLevel == 1)
        #expect(decoded.padLayers.isEmpty)
    }
}

@Suite("UMP parsing")
struct UMPParsingTests {
    @Test("Note off and note on at velocity zero both arrive as a release")
    func releases() {
        let events = MidiEngine.events(words: [0x2080_3C40, 0x2090_3C00, 0x2090_3C64])
        #expect(events.count == 3)
        guard events.count == 3 else { return }
        if case .noteOff(1, 60) = events[0] {} else { Issue.record("0x8 was not a release: \(events[0])") }
        if case .noteOff(1, 60) = events[1] {} else { Issue.record("velocity 0 was not a release: \(events[1])") }
        if case .note(1, 60, 100) = events[2] {} else { Issue.record("note on lost: \(events[2])") }
    }
}

/// Momentary play and the sustain pedal, the way a keyboard player expects them.
@MainActor
@Suite("Sustain pedal", .serialized)
struct SustainPedalTests {

    private func model(latch: Bool, inverted: Bool = false) -> AppModel {
        let id = UUID().uuidString
        let app = AppModel(defaults: UserDefaults(suiteName: "vigil.tests.\(id)")!,
                           samplesDirectory: FileManager.default.temporaryDirectory
                               .appendingPathComponent("vigil-tests/\(id)", isDirectory: true))
        app.start()
        app.settings.padLatch = latch
        app.settings.sustainInverted = inverted
        return app
    }

    @Test("Latched, releasing the key leaves the pad sounding")
    func latchedIgnoresRelease() {
        let app = model(latch: true)
        app.midi.onEvent?(.note(channel: 1, number: 62, velocity: 100))
        app.midi.onEvent?(.noteOff(channel: 1, number: 62))
        #expect(app.tonal.activeNote == .D)
    }

    @Test("Momentary, the pad plays while the key is down")
    func momentaryFollowsKey() {
        let app = model(latch: false)
        app.midi.onEvent?(.note(channel: 1, number: 62, velocity: 100))
        #expect(app.tonal.activeNote == .D)
        app.midi.onEvent?(.note(channel: 1, number: 62, velocity: 100))
        #expect(app.tonal.activeNote == .D, "a second press does not toggle it off")
        app.midi.onEvent?(.noteOff(channel: 1, number: 62))
        #expect(app.tonal.activeNote == nil)
    }

    @Test("Releasing an older key does not stop the newer one")
    func olderReleaseIsIgnored() {
        let app = model(latch: false)
        app.midi.onEvent?(.note(channel: 1, number: 62, velocity: 100))
        app.midi.onEvent?(.note(channel: 1, number: 64, velocity: 100))
        app.midi.onEvent?(.noteOff(channel: 1, number: 62))
        #expect(app.tonal.activeNote == .E)
    }

    @Test("The pedal holds a released key until it comes up")
    func pedalHolds() {
        let app = model(latch: false)
        app.midi.onEvent?(.control(channel: 1, number: 64, value: 127))
        app.midi.onEvent?(.note(channel: 1, number: 62, velocity: 100))
        app.midi.onEvent?(.noteOff(channel: 1, number: 62))
        #expect(app.tonal.activeNote == .D)
        app.midi.onEvent?(.control(channel: 1, number: 64, value: 0))
        #expect(app.tonal.activeNote == nil)
    }

    @Test("Lifting the pedal while the key is still down keeps the pad")
    func pedalUpWithKeyDown() {
        let app = model(latch: false)
        app.midi.onEvent?(.control(channel: 1, number: 64, value: 127))
        app.midi.onEvent?(.note(channel: 1, number: 62, velocity: 100))
        app.midi.onEvent?(.control(channel: 1, number: 64, value: 0))
        #expect(app.tonal.activeNote == .D)
    }

    @Test("Switching modes forgets keys held before, so the pedal can stop the pad again")
    func modeSwitchClearsHeldKeys() {
        let app = model(latch: false)
        app.midi.onEvent?(.note(channel: 1, number: 62, velocity: 100))
        app.settings.padLatch = true
        app.midi.onEvent?(.noteOff(channel: 1, number: 62))
        app.settings.padLatch = false
        app.midi.onEvent?(.control(channel: 1, number: 64, value: 127))
        app.midi.onEvent?(.control(channel: 1, number: 64, value: 0))
        #expect(app.tonal.activeNote == nil)
    }

    @Test("An inverted pedal reads low as down")
    func invertedPolarity() {
        let app = model(latch: false, inverted: true)
        app.midi.onEvent?(.control(channel: 1, number: 64, value: 0))
        app.midi.onEvent?(.note(channel: 1, number: 62, velocity: 100))
        app.midi.onEvent?(.noteOff(channel: 1, number: 62))
        #expect(app.tonal.activeNote == .D)
        app.midi.onEvent?(.control(channel: 1, number: 64, value: 127))
        #expect(app.tonal.activeNote == nil)
    }
}

/// Second-pass tonal pad tools, measured on the rendered signal. Shapes are compared level
/// independently, since the crossfade ramp is a `Task` that a busy main actor can delay.
@MainActor
@Suite("Pad lab tone", .serialized)
struct PadLabToneTests {

    private func render(sound: String = "Default", configure: (TonalPadEngine) -> Void) async throws -> [Float] {
        let graph = AudioGraph(preparesImmediately: false)
        let tonal = TonalPadEngine(graph: graph, catalog: FactoryCatalog())
        tonal.crossfade = 0.05
        tonal.master = 1
        tonal.selectSound(sound)
        configure(tonal)
        let captured = try await OfflineRender.capture(
            graph, seconds: 1.5, settle: .milliseconds(300),
            prepare: { tonal.toggle(.C) }, pump: {}
        )
        return Array(captured.samples.suffix(captured.samples.count / 2))
    }

    private func shapeDifference(_ a: [Float], _ b: [Float]) -> Float {
        let scaleA = max(OfflineRender.rms(a), 1e-9), scaleB = max(OfflineRender.rms(b), 1e-9)
        return OfflineRender.rms(zip(a, b).map { $0 / scaleA - $1 / scaleB })
    }

    /// Second difference over level: weights the top of the spectrum far more than the first
    /// difference, which barely moves on these warm pads.
    private func edge(_ samples: [Float]) -> Float {
        guard samples.count > 2 else { return 0 }
        var total: Float = 0
        for index in 2..<samples.count {
            let curve = samples[index] - 2 * samples[index - 1] + samples[index - 2]
            total += curve * curve
        }
        return (total / Float(samples.count - 2)).squareRoot() / max(OfflineRender.rms(samples), 1e-9)
    }

    @Test("Boosting the high band brightens the pad, cutting the low band thins it")
    func toneBands() async throws {
        let flat = try await render(sound: "Synth") { _ in }
        let bright = try await render(sound: "Synth") { $0.highGain = 12 }
        let thin = try await render(sound: "Synth") { $0.lowGain = -12 }
        #expect(edge(bright) > edge(flat) * 1.3, "high band: \(edge(bright)) against \(edge(flat))")
        #expect(OfflineRender.weight(thin) < OfflineRender.weight(flat) * 0.95)
    }

    @Test("The compressor brings a loud pad down, and off it does nothing")
    func compressor() async throws {
        let off = try await render { $0.compressorEnabled = false }
        let on = try await render { $0.compressorEnabled = true; $0.compressorThreshold = -40; $0.compressorGain = 0 }
        #expect(OfflineRender.rms(off) > 0.001)
        #expect(OfflineRender.rms(on) < OfflineRender.rms(off) * 0.6)
    }

    @Test("A second layer joins the sound, and at zero it is silent")
    func layers() async throws {
        let single = try await render { _ in }
        let muted = try await render { $0.setLayers([PadLayer(soundID: "Shimmer", level: 0)]) }
        let mixed = try await render { $0.setLayers([PadLayer(soundID: "Shimmer", level: 1)]) }
        #expect(shapeDifference(single, muted) < 0.01, "a layer at zero still sounds")
        #expect(shapeDifference(single, mixed) > 0.2, "the second layer did not join")
    }

    @Test("Changing a layer's level does not restart the note")
    func levelChangeKeepsNote() async throws {
        let graph = AudioGraph(preparesImmediately: false)
        let tonal = TonalPadEngine(graph: graph, catalog: FactoryCatalog())
        tonal.setLayers([PadLayer(soundID: "Shimmer", level: 0.5)])
        tonal.toggle(.C)
        tonal.setLayers([PadLayer(soundID: "Shimmer", level: 0.9)])
        #expect(tonal.activeNote == .C)
        #expect(tonal.layers.count == 1)
    }
}

@MainActor
@Suite("Pad lab drums", .serialized)
struct PadLabDrumTests {

    private func render(seconds: Double, configure: (DrumEngine, DrumPad, AudioGraph) -> Void) async throws -> (samples: [Float], rate: Double, hitSeconds: Double) {
        let graph = AudioGraph(preparesImmediately: false)
        let drums = DrumEngine(graph: graph)
        let catalog = FactoryCatalog()
        let kit = try #require(catalog.kit(id: "DrumKit1"))
        let slot = try #require(kit.slots.first { $0.name == "Clap 1" } ?? kit.slots.first)
        let url = try #require(catalog.url(for: slot.file))
        let pad = drums.pads[0]
        try drums.load(url: url, into: pad, name: slot.name, source: .native(kit: kit.id, slot: 0))
        pad.trim = 0...0.04
        configure(drums, pad, graph)
        let played = try #require(pad.playBuffer)
        let captured = try await OfflineRender.capture(graph, seconds: seconds, prepare: { drums.trigger(pad) }, pump: {})
        return (captured.samples, captured.sampleRate, Double(played.frameLength) / played.format.sampleRate)
    }

    @Test("A reverb send leaves a tail after the hit has ended")
    func reverbTail() async throws {
        let dry = try await render(seconds: 1.5) { _, pad, _ in pad.reverbSend = 0 }
        let wet = try await render(seconds: 1.5) { drums, pad, _ in pad.reverbSend = 1; drums.reverbLevel = 1 }
        let after = Int((dry.hitSeconds + 0.1) * dry.rate)
        let dryTail = OfflineRender.rms(Array(dry.samples[after...]))
        let wetTail = OfflineRender.rms(Array(wet.samples[after...]))
        #expect(wetTail > max(dryTail * 4, 0.0005), "tail \(wetTail) against dry \(dryTail)")
    }

    @Test("The drum high-pass thins the hit")
    func drumHighpass() async throws {
        let full = try await render(seconds: 0.5) { _, _, _ in }
        let thin = try await render(seconds: 0.5) { drums, _, _ in drums.highpass = Settings.highpassRange.upperBound }
        #expect(OfflineRender.weight(thin.samples) < OfflineRender.weight(full.samples) * 0.9)
    }

    @Test("The output delay moves every sound later by its time")
    func outputDelay() async throws {
        let now = try await render(seconds: 0.6) { _, _, _ in }
        let later = try await render(seconds: 0.6) { _, _, graph in graph.outputDelay = 0.1 }
        let first = try #require(OfflineRender.onsets(in: now.samples, rate: now.rate).first)
        let delayed = try #require(OfflineRender.onsets(in: later.samples, rate: later.rate).first)
        let shift = Double(delayed - first) / now.rate
        #expect(abs(shift - 0.1) < 0.01, "shifted by \(shift) s")
    }
}

@MainActor
@Suite("Pad lab drum persistence", .serialized)
struct PadLabDrumPersistenceTests {
    @Test("A pad's reverb send is saved and comes back")
    func sendPersists() {
        let id = UUID().uuidString
        let defaults = UserDefaults(suiteName: "vigil.tests.\(id)")!
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("vigil-tests/\(id)", isDirectory: true)
        let first = AppModel(defaults: defaults, samplesDirectory: directory)
        first.start()
        first.setReverbSend(first.drums.pads[1], to: 0.7)
        #expect(first.isKitModified)
        first.flushPendingWrites()

        let second = AppModel(defaults: defaults, samplesDirectory: directory)
        second.start()
        #expect(second.drums.pads[1].reverbSend == 0.7)
        #expect(second.drums.pads[0].reverbSend == 0)
    }
}
