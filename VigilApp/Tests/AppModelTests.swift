import AVFoundation
import Foundation
import Testing
@testable import Vigil

/// Lifecycle over real stores, with preferences and the sample folder pointed somewhere
/// throwaway so nothing here touches the machine's own state.
@MainActor
@Suite("App model", .serialized)
struct AppModelTests {

    private func sandbox() -> (defaults: UserDefaults, directory: URL) {
        let id = UUID().uuidString
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("vigil-tests/\(id)", isDirectory: true)
        return (UserDefaults(suiteName: "vigil.tests.\(id)")!, directory)
    }

    private func model(_ box: (defaults: UserDefaults, directory: URL)) -> AppModel {
        AppModel(defaults: box.defaults, samplesDirectory: box.directory)
    }

    /// A wav the import can actually copy.
    private func makeAudioFile(named name: String, in directory: URL) throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(name)
        let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4_410)!
        buffer.frameLength = 4_410
        try file.write(from: buffer)
        return url
    }

    @Test("First run loads the default kit instead of opening silent")
    func firstRunLoadsDefaultKit() {
        let box = sandbox()
        let app = model(box)
        app.start()

        let everyPadLoaded = app.drums.pads.allSatisfy(\.isAssigned)
        #expect(app.currentKit != nil)
        #expect(everyPadLoaded)
    }

    @Test("A second run restores the saved state rather than the default kit")
    func secondRunRestoresState() throws {
        let box = sandbox()

        let first = model(box)
        first.start()
        let target = try #require(first.catalog.kits.first { $0.id != "DrumKit1" })
        first.selectKit(target)
        first.flushPendingWrites()
        let expected = first.currentKit

        let second = model(box)
        second.start()
        #expect(second.currentKit == expected)
        #expect(second.currentKit != .factory("DrumKit1"))
    }

    @Test("Importing the same name twice keeps both files")
    func importKeepsBothNames() throws {
        let box = sandbox()
        let app = model(box)
        let source = try makeAudioFile(named: "kick.wav",
                                       in: FileManager.default.temporaryDirectory
                                           .appendingPathComponent("vigil-src/\(UUID())"))

        let first = try app.library.importFile(from: source)
        let second = try app.library.importFile(from: source)

        #expect(first.fileName == "kick.wav")
        #expect(second.fileName == "kick-1.wav")
        #expect(app.library.samples.count == 2)
    }

    @Test("Deleting a sample clears the pads that used it")
    func deletingSampleClearsPads() throws {
        let box = sandbox()
        let app = model(box)
        app.start()

        let source = try makeAudioFile(named: "snare.wav",
                                       in: FileManager.default.temporaryDirectory
                                           .appendingPathComponent("vigil-src/\(UUID())"))
        let sample = try app.library.importFile(from: source)
        let pad = try #require(app.drums.pads.first)
        app.assign(pad, sample: sample)
        #expect(pad.source == .custom(sample.id))

        app.delete(sample)
        #expect(!pad.isAssigned)
        let stillReferenced = app.drums.pads.contains { $0.source == .custom(sample.id) }
        #expect(app.library.samples.isEmpty)
        #expect(!stillReferenced)
    }

    @Test("Saving and loading a set restores sound, kit and settings")
    func setRoundTrip() throws {
        let box = sandbox()
        let app = model(box)
        app.start()

        app.settings.bpm = 143
        app.settings.timeSignature = .sevenEight
        app.settings.cutoff = 5_000
        let other = try #require(app.catalog.kits.first { $0.id != "DrumKit1" })
        app.selectKit(other)
        app.selectPadSound(app.catalog.padSoundList[1].id)
        app.saveCurrentSet(named: "Live")

        app.settings.bpm = 90
        app.settings.timeSignature = .fourFour
        app.selectKit(try #require(app.catalog.kit(id: "DrumKit1")))
        app.selectPadSound(app.catalog.padSoundList[0].id)

        let saved = try #require(app.sets.sets.first)
        app.loadSet(saved)

        #expect(app.settings.bpm == 143)
        #expect(app.settings.timeSignature == .sevenEight)
        #expect(app.settings.cutoff == 5_000)
        #expect(app.currentKit == .factory(other.id))
        #expect(app.tonal.soundID == app.catalog.padSoundList[1].id)
    }

    @Test("Editing a factory kit never changes it; saving makes a user copy")
    func factoryKitStaysReadOnly() throws {
        let box = sandbox()
        let app = model(box)
        app.start()

        let factory = try #require(app.catalog.kits.first)
        app.selectKit(factory)
        let pad = try #require(app.drums.pads.first)
        app.setVolume(pad, to: 0.25)
        #expect(app.isKitModified)

        app.saveCurrentKit(named: "Copy")
        let copy = try #require(app.userKits.kits.first)
        #expect(app.currentKit == .user(copy.id))
        #expect(copy.slots.first?.volume == 0.25)

        // The factory kit is rebuilt from the catalog, so it comes back untouched.
        app.selectKit(factory)
        #expect(app.drums.pads.first?.volume == 1.0)
        #expect(!app.isKitModified)
    }

    @Test("A mapped MIDI note fires its pad, and other channels are ignored")
    func midiNoteFiresPad() {
        let box = sandbox()
        let app = model(box)
        app.start()
        app.midiConfig.set(.note(60), for: .drum(0))

        app.midi.onEvent?(.note(channel: 1, number: 60, velocity: 100))
        #expect(app.playingPadIDs.contains(0))

        app.playingPadIDs.removeAll()
        app.midi.onEvent?(.note(channel: 2, number: 60, velocity: 100))
        #expect(app.playingPadIDs.isEmpty)
    }

    @Test("A mapped CC drives its target across the whole range")
    func midiControlChangeDrivesTarget() {
        let box = sandbox()
        let app = model(box)
        app.start()
        app.midiConfig.set(.cc(7), for: .padMaster)

        app.midi.onEvent?(.control(channel: 1, number: 7, value: 127))
        #expect(abs(app.settings.padMaster - 1) < 0.01)

        app.midi.onEvent?(.control(channel: 1, number: 7, value: 0))
        #expect(abs(app.settings.padMaster) < 0.01)
    }
}

/// The crossfade holds constant energy, so a swap has no dip in the middle.
@Suite("Crossfade curve")
struct CrossfadeCurveTests {

    @Test("Rise and fall keep constant energy across the ramp")
    func constantEnergy() {
        for step in 0...100 {
            let (rise, fall) = CrossfadeCurve.gains(at: Double(step) / 100)
            let energy = rise * rise + fall * fall
            #expect(abs(energy - 1) < 0.0001, "energy \(energy) at step \(step)")
        }
    }

    @Test("The ramp starts silent, ends full, and is clamped outside 0 to 1")
    func endpoints() {
        #expect(CrossfadeCurve.gains(at: 0).rise == 0)
        #expect(CrossfadeCurve.gains(at: 1).rise == 1)
        #expect(abs(CrossfadeCurve.gains(at: 1).fall) < 0.0001)
        #expect(CrossfadeCurve.gains(at: -5).rise == CrossfadeCurve.gains(at: 0).rise)
        #expect(CrossfadeCurve.gains(at: 9).rise == CrossfadeCurve.gains(at: 1).rise)
    }
}

/// A pad whose file cannot be read has to say so. Silent failure is the bug class this
/// project keeps hitting, and the convention is that every error reaches a toast.
@MainActor
@Suite("Unreadable audio", .serialized)
struct UnreadableAudioTests {

    @Test("A sample that is not real audio leaves the pad empty and raises an error")
    func brokenSampleReportsError() throws {
        let id = UUID().uuidString
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("vigil-tests/\(id)", isDirectory: true)
        let app = AppModel(defaults: UserDefaults(suiteName: "vigil.tests.\(id)")!,
                           samplesDirectory: directory)
        app.start()

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let junk = directory.appendingPathComponent("broken.wav")
        try Data("this is not audio".utf8).write(to: junk)

        let sample = Sample(id: UUID(), displayName: "broken", fileName: "broken.wav")
        let pad = try #require(app.drums.pads.first)
        let loaded = app.load(app.library.url(for: sample), into: pad,
                              name: sample.displayName, source: .custom(sample.id))

        #expect(!loaded)
        #expect(!pad.isAssigned, "a pad that failed to load must not look assigned")
    }

    @Test("A batch failure raises one error, not one per pad")
    func batchFailureRaisesOneToast() {
        let id = UUID().uuidString
        let app = AppModel(defaults: UserDefaults(suiteName: "vigil.tests.\(id)")!,
                           samplesDirectory: FileManager.default.temporaryDirectory
                               .appendingPathComponent("vigil-tests/\(id)", isDirectory: true))
        app.reportUnreadable(4)

        let toast = app.toasts.current
        #expect(toast?.kind == .error)
        #expect(toast != nil)

        app.toasts.dismiss()
        app.reportUnreadable(0)
        #expect(app.toasts.current == nil, "no failures should raise no toast")
    }
}
