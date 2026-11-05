import Foundation
import Testing
@testable import Vigil

/// The stage screen prints each pad's computer key on the pad itself, so the hint has to
/// follow the mapping table rather than a hard-coded layout.
@MainActor
@Suite("Stage")
struct StageTests {

    private func config() -> MidiConfig {
        MidiConfig(defaults: UserDefaults(suiteName: "vigil.tests.stage.\(UUID().uuidString)")!)
    }

    @Test("A note shows its default computer key")
    func defaultHint() throws {
        let midi = config()
        let expected = try #require(MidiTarget.tonal(.C).defaultKey)
        #expect(midi.keyHint(for: .tonal(.C)) == expected.uppercased())
    }

    @Test("Learning a MIDI note keeps the computer key as the hint")
    func midiDoesNotReplaceHint() {
        let midi = config()
        let before = midi.keyHint(for: .drum(0))
        midi.set(.note(60), for: .drum(0))
        #expect(midi.keyHint(for: .drum(0)) == before)
    }

    @Test("A cleared target shows no hint")
    func clearedHasNone() {
        let midi = config()
        midi.clear(.tonal(.D))
        #expect(midi.keyHint(for: .tonal(.D)) == nil)
    }

    @Test("A relearned key moves the hint to its new owner")
    func relearnedKeyMoves() {
        let midi = config()
        midi.set(.key("z"), for: .tonal(.E))
        #expect(midi.keyHint(for: .tonal(.E)) == "Z")
    }
}
