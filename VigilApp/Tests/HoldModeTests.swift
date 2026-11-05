import Foundation
import Testing
@testable import Vigil

/// Latch and hold have to mean the same thing on screen and on the computer keyboard as they
/// do on a MIDI controller: latch toggles, hold plays only while pressed.
@MainActor
@Suite("Hold mode on screen and keyboard", .serialized)
struct HoldModeTests {

    private func model(latch: Bool) -> AppModel {
        let id = UUID().uuidString
        let app = AppModel(defaults: UserDefaults(suiteName: "vigil.tests.\(id)")!,
                           samplesDirectory: FileManager.default.temporaryDirectory
                               .appendingPathComponent("vigil-tests/\(id)", isDirectory: true))
        app.start()
        app.settings.padLatch = latch
        return app
    }

    @Test("Hold: a pressed note sounds until it is released")
    func holdFollowsPress() {
        let app = model(latch: false)
        app.pressNote(.D)
        #expect(app.tonal.activeNote == .D)
        app.releaseNote(.D)
        #expect(app.tonal.activeNote == nil)
    }

    @Test("Hold: pressing a second note while the first is held switches to it")
    func holdSwitchesNote() {
        let app = model(latch: false)
        app.pressNote(.D)
        app.pressNote(.G)
        #expect(app.tonal.activeNote == .G)
        app.releaseNote(.D)
        #expect(app.tonal.activeNote == .G, "releasing the old note leaves the held one sounding")
        app.releaseNote(.G)
        #expect(app.tonal.activeNote == nil)
    }

    @Test("Latch: release does nothing and a second press stops the note")
    func latchToggles() {
        let app = model(latch: true)
        app.pressNote(.D)
        app.releaseNote(.D)
        #expect(app.tonal.activeNote == .D)
        app.pressNote(.D)
        #expect(app.tonal.activeNote == nil)
    }

    @Test("Hold: a computer key plays its note until the key comes up")
    func holdOnComputerKey() throws {
        let app = model(latch: false)
        let key = try #require(MidiTarget.tonal(.C).defaultKey)
        let character = try #require(key.first)
        #expect(app.handleKey(character))
        #expect(app.tonal.activeNote == .C)
        #expect(app.handleKeyUp(character))
        #expect(app.tonal.activeNote == nil)
    }

    @Test("Latch: a computer key toggles and its release is ignored")
    func latchOnComputerKey() throws {
        let app = model(latch: true)
        let character = try #require(MidiTarget.tonal(.C).defaultKey?.first)
        _ = app.handleKey(character)
        _ = app.handleKeyUp(character)
        #expect(app.tonal.activeNote == .C)
    }

    @Test("A mapped key coming up or repeating is consumed, so macOS does not beep")
    func mappedKeyEventsAreConsumed() throws {
        let app = model(latch: true)
        let note = try #require(MidiTarget.tonal(.C).defaultKey?.first)
        let drum = try #require(MidiTarget.drum(0).defaultKey?.first)
        #expect(app.handleKey(note))
        #expect(app.handleKeyRepeat(note))
        #expect(app.tonal.activeNote == .C, "a held key repeating does not toggle the note off")
        #expect(app.handleKeyUp(note))
        #expect(app.handleKeyUp(drum))
        #expect(app.handleKeyRepeat(drum))
    }

    @Test("An unmapped key is left alone")
    func unmappedKeyIsIgnored() {
        let app = model(latch: true)
        app.midiConfig.clearAll()
        #expect(!app.handleKeyUp("q"))
        #expect(!app.handleKeyRepeat("q"))
    }
}
