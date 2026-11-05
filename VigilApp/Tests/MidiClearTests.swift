import Foundation
import Testing
@testable import Vigil

/// Nothing plays from MIDI without a mapping. The defaults are ordinary mappings, so clearing
/// them leaves a connected controller silent until something is learned or restored.
@MainActor
@Suite("Clearing MIDI mappings", .serialized)
struct MidiClearTests {

    private func model(_ store: UserDefaults? = nil) -> (AppModel, UserDefaults) {
        let id = UUID().uuidString
        let defaults = store ?? UserDefaults(suiteName: "vigil.tests.\(id)")!
        let app = AppModel(defaults: defaults,
                           samplesDirectory: FileManager.default.temporaryDirectory
                               .appendingPathComponent("vigil-tests/\(id)", isDirectory: true))
        app.start()
        return (app, defaults)
    }

    @Test("The defaults are visible mappings, not a hidden fallback")
    func defaultsAreMappings() {
        let (app, _) = model()
        #expect(app.midiConfig.target(for: .note(60)) == .tonal(.C))
        #expect(app.midiConfig.target(for: .note(36)) == .drum(0))
    }

    @Test("After clearing, notes play neither the tonal pad nor the drums")
    func clearedIsSilent() throws {
        let (app, _) = model()
        app.midiConfig.clearAll()
        app.midi.onEvent?(.note(channel: 1, number: 62, velocity: 100))
        #expect(app.tonal.activeNote == nil)
        let pad = try #require(app.drums.pads.first)
        app.midi.onEvent?(.note(channel: 10, number: 36, velocity: 100))
        app.midi.onEvent?(.note(channel: 1, number: 36, velocity: 100))
        #expect(!pad.isFlashing)
    }

    @Test("After clearing, a learned note still plays its target")
    func learnedAfterClearPlays() {
        let (app, _) = model()
        app.midiConfig.clearAll()
        app.midiConfig.set(.note(62), for: .tonal(.D))
        app.midi.onEvent?(.note(channel: 1, number: 62, velocity: 100))
        #expect(app.tonal.activeNote == .D)
    }

    @Test("Restoring the defaults brings back the computer keys and the MIDI notes")
    func restoreBringsBothBack() {
        let (app, _) = model()
        app.midiConfig.clearAll()
        app.midiConfig.restoreDefaults()
        #expect(app.midiConfig.keyHint(for: .tonal(.C)) != nil)
        app.midi.onEvent?(.note(channel: 1, number: 62, velocity: 100))
        #expect(app.tonal.activeNote == .D)
    }

    @Test("The cleared state survives a relaunch")
    func clearedPersists() {
        let (first, store) = model()
        first.midiConfig.clearAll()
        let reloaded = MidiConfig(defaults: store)
        #expect(reloaded.target(for: .note(60)) == nil)
    }

    @Test("Clearing keeps the panic CCs working")
    func panicSurvivesClear() {
        let (app, _) = model()
        app.toggleNote(.C)
        app.midiConfig.clearAll()
        app.midi.onEvent?(.control(channel: 1, number: 123, value: 127))
        #expect(app.tonal.activeNote == nil)
    }
}
