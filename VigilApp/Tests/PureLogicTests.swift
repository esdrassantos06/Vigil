import Foundation
import Testing
@testable import Vigil

@Suite("Note labels")
struct NoteLabelTests {
    @Test("Sharp and flat spellings")
    func accidental() {
        #expect(Note.Cs.label(sharps: true) == "C#")
        #expect(Note.Cs.label(sharps: false) == "Db")
        #expect(Note.Ds.label(sharps: false) == "Eb")
        #expect(Note.As.label(sharps: false) == "Bb")
        #expect(Note.C.label(sharps: false) == "C")
    }

    @Test("Minor shows the relative, three semitones down")
    func relativeMinor() {
        #expect(Note.C.label(sharps: true, major: false) == "Am")
        #expect(Note.G.label(sharps: true, major: false) == "Em")
        #expect(Note.Ds.label(sharps: true, major: false) == "Cm")
        #expect(Note.A.label(sharps: false, major: false) == "Gbm")
    }
}

@Suite("Time signatures")
struct TimeSignatureTests {
    @Test("Beats per bar")
    func beats() {
        #expect(TimeSignature.threeFour.beatsPerBar == 3)
        #expect(TimeSignature.fourFour.beatsPerBar == 4)
        #expect(TimeSignature.fiveFour.beatsPerBar == 5)
        #expect(TimeSignature.sixEight.beatsPerBar == 6)
        #expect(TimeSignature.sevenEight.beatsPerBar == 7)
        #expect(TimeSignature.twelveEight.beatsPerBar == 12)
    }

    @Test("In x/8 the beat is the eighth note, half of x/4")
    func beatUnit() {
        for signature in [TimeSignature.threeFour, .fourFour, .fiveFour] {
            #expect(signature.beatUnit == 4)
        }
        for signature in [TimeSignature.sixEight, .sevenEight, .twelveEight] {
            #expect(signature.beatUnit == 8)
        }
    }

    @Test("All six signatures exist")
    func allCases() {
        #expect(TimeSignature.allCases.count == 6)
        #expect(TimeSignature.allCases.map(\.rawValue)
            == ["3/4", "4/4", "5/4", "6/8", "7/8", "12/8"])
    }
}

@Suite("Coding")
struct CodableTests {
    @Test("Settings survives a round trip")
    func settings() throws {
        var original = Settings()
        original.bpm = 137
        original.timeSignature = .sevenEight
        original.clickSound = .cowbell
        original.cutoff = 4_200
        original.sharps = false
        original.doubleTime = true

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Settings.self, from: data)
        #expect(decoded == original)
    }

    @Test("PadSource in all three cases")
    func padSource() throws {
        let id = UUID()
        let sources: [PadSource] = [.empty, .custom(id), .native(kit: "WorshipDrums", slot: 5)]
        for source in sources {
            let data = try JSONEncoder().encode(source)
            #expect(try JSONDecoder().decode(PadSource.self, from: data) == source)
        }
    }

    @Test("KitRef for factory and user kits")
    func kitRef() throws {
        let refs: [KitRef] = [.factory("EFX1"), .user(UUID())]
        for ref in refs {
            let data = try JSONEncoder().encode(ref)
            #expect(try JSONDecoder().decode(KitRef.self, from: data) == ref)
        }
    }

    @Test("An older set that still carried eight slots still decodes")
    func legacySetDecodes() throws {
        let json = """
        {"id":"\(UUID().uuidString)","name":"Memes","padSoundID":"Default",
         "kit":{"factory":{"_0":"WorshipDrums"}},
         "slots":[{"volume":1,"color":"coral","source":{"empty":{}}}],
         "settings":\(String(data: try JSONEncoder().encode(Settings()), encoding: .utf8)!)}
        """
        let set = try JSONDecoder().decode(VigilSet.self, from: Data(json.utf8))
        #expect(set.name == "Memes")
        #expect(set.kit == .factory("WorshipDrums"))
    }
}

@MainActor
@Suite("MIDI mapping")
struct MidiConfigTests {
    /// A throwaway suite per call, so the tests never touch the real preferences.
    private func freshConfig() -> MidiConfig {
        MidiConfig(defaults: UserDefaults(suiteName: "vigil.tests.\(UUID())")!)
    }

    @Test("Default computer keys")
    func defaults() {
        let config = freshConfig()
        #expect(config.binding(for: .tonal(.C), keyboard: true) == .key("a"))
        #expect(config.binding(for: .tonal(.B), keyboard: true) == .key("j"))
        #expect(config.binding(for: .drum(0), keyboard: true) == .key("z"))
        #expect(config.binding(for: .drum(7), keyboard: true) == .key(","))
        #expect(config.binding(for: .stop, keyboard: true) == nil)
    }

    @Test("A key and a note coexist on one target")
    func keyAndNoteCoexist() {
        let config = freshConfig()
        config.set(.note(60), for: .tonal(.C))
        #expect(config.binding(for: .tonal(.C), keyboard: true) == .key("a"))
        #expect(config.binding(for: .tonal(.C), keyboard: false) == .note(60))
    }

    @Test("Learning replaces only the shortcut of the same kind")
    func sameKindReplaced() {
        let config = freshConfig()
        config.set(.note(60), for: .tonal(.C))
        config.set(.cc(7), for: .tonal(.C))
        #expect(config.binding(for: .tonal(.C), keyboard: false) == .cc(7))
        #expect(config.binding(for: .tonal(.C), keyboard: true) == .key("a"))
    }

    @Test("A shortcut serves one target, so learning takes it from the previous owner")
    func stealsFromPreviousOwner() {
        let config = freshConfig()
        config.set(.key("a"), for: .tonal(.D))
        #expect(config.binding(for: .tonal(.D), keyboard: true) == .key("a"))
        #expect(config.binding(for: .tonal(.C), keyboard: true) == nil)
        #expect(config.target(for: .key("a")) == .tonal(.D))
    }

    @Test("Clearing one kind leaves the other alone")
    func clearOneKind() {
        let config = freshConfig()
        config.set(.note(64), for: .drum(2))
        config.clear(.drum(2), keyboard: false)
        #expect(config.binding(for: .drum(2), keyboard: false) == nil)
        #expect(config.binding(for: .drum(2), keyboard: true) == .key("c"))
    }

    @Test("Restoring default keys keeps what came from the controller")
    func restoreKeepsMidi() {
        let config = freshConfig()
        config.set(.note(60), for: .tonal(.C))
        config.set(.key("q"), for: .tonal(.C))
        config.restoreDefaults()
        #expect(config.binding(for: .tonal(.C), keyboard: true) == .key("a"))
        #expect(config.binding(for: .tonal(.C), keyboard: false) == .note(60))
    }

    @Test("Clearing mappings wipes everything")
    func clearAll() {
        let config = freshConfig()
        config.clearAll()
        #expect(config.bindings.isEmpty)
        #expect(config.target(for: .key("a")) == nil)
    }
}
