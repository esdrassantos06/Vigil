import CoreMIDI
import Foundation
import Testing
@testable import Vigil

@MainActor
@Suite("Resource cleanup")
struct CleanupTests {

    private func library() -> (SampleLibrary, URL) {
        let id = UUID().uuidString
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("vigil-tests/\(id)", isDirectory: true)
        return (SampleLibrary(defaults: UserDefaults(suiteName: "vigil.tests.\(id)")!,
                              directory: directory), directory)
    }

    private func makeAudioFile(in directory: URL, named name: String) throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(name)
        try Data("not really audio".utf8).write(to: url)
        return url
    }

    @Test("Deleting a sample takes its file with it")
    func deleteRemovesFile() throws {
        let (library, directory) = library()
        let source = try makeAudioFile(in: directory.appendingPathComponent("in"), named: "clap.wav")
        let sample = try library.importFile(from: source)
        let stored = library.url(for: sample)
        #expect(FileManager.default.fileExists(atPath: stored.path))

        try library.delete(sample)

        #expect(!FileManager.default.fileExists(atPath: stored.path))
        #expect(library.samples.isEmpty)
    }

    @Test("A sample whose file already vanished still leaves the library")
    func deleteToleratesMissingFile() throws {
        let (library, directory) = library()
        let source = try makeAudioFile(in: directory.appendingPathComponent("in"), named: "clap.wav")
        let sample = try library.importFile(from: source)
        try FileManager.default.removeItem(at: library.url(for: sample))

        try library.delete(sample)
        #expect(library.samples.isEmpty)
    }

    @Test("A file that refuses to go keeps its entry instead of orphaning itself")
    func deleteReportsFailure() throws {
        let (library, directory) = library()
        let source = try makeAudioFile(in: directory.appendingPathComponent("in"), named: "clap.wav")
        let sample = try library.importFile(from: source)

        // Removing a file needs write permission on its directory, not on the file.
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: directory.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path) }

        #expect(throws: LibraryError.self) { try library.delete(sample) }
        #expect(library.samples.count == 1, "the entry has to stay, or the file is orphaned")
    }

    @Test("Stopping MIDI disposes the client, and starting again still works")
    func midiStopIsCleanAndRepeatable() throws {
        let engine = MidiEngine()
        try engine.start()
        engine.stop()
        engine.stop()
        try engine.start()
        engine.stop()
    }
}
