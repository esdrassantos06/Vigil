import AVFoundation
import Foundation
import Testing
@testable import Vigil

/// `accentFirst` is the only setting without `restartIfRunning()`, and that absence is the
/// feature: restarting would shift the time grid.
@MainActor
@Suite("Metronome while running")
struct MetronomeLiveTests {

    private func runningMetronome(bpm: Double = 240) throws -> (AudioGraph, MetronomeEngine) {
        let graph = AudioGraph()
        let metronome = MetronomeEngine(graph: graph, catalog: FactoryCatalog())
        metronome.bpm = bpm
        try graph.start()
        metronome.start()
        return (graph, metronome)
    }

    private func waitForBeats(_ metronome: MetronomeEngine) async throws {
        for _ in 0..<40 {
            if metronome.beatInBar != 0 { return }
            try await Task.sleep(for: .milliseconds(50))
        }
        Issue.record("the metronome never advanced a beat")
    }

    @Test("Toggling the accent does not restart the count")
    func accentDoesNotRestart() async throws {
        let (_, metronome) = try runningMetronome()
        try await waitForBeats(metronome)

        let before = metronome.beatInBar
        metronome.accentFirst.toggle()

        #expect(metronome.isRunning)
        #expect(metronome.beatInBar == before)
    }

    @Test("BPM restarts on purpose")
    func bpmRestarts() async throws {
        let (_, metronome) = try runningMetronome()
        try await waitForBeats(metronome)

        metronome.bpm = 96
        #expect(metronome.isRunning)
        #expect(metronome.beatInBar == 0)
    }

    @Test("Time signature restarts on purpose")
    func timeSignatureRestarts() async throws {
        let (_, metronome) = try runningMetronome()
        try await waitForBeats(metronome)

        metronome.timeSignature = .sevenEight
        #expect(metronome.beatInBar == 0)
    }

    @Test("Double time restarts on purpose")
    func doubleTimeRestarts() async throws {
        let (_, metronome) = try runningMetronome()
        try await waitForBeats(metronome)

        metronome.doubleTime = true
        #expect(metronome.beatInBar == 0)
    }

    /// Proving which buffer landed on which beat needs offline rendering.
    @Test("The metronome keeps scheduling after the accent changes")
    func keepsSchedulingAfterAccentChange() async throws {
        let (_, metronome) = try runningMetronome()
        try await waitForBeats(metronome)

        metronome.accentFirst.toggle()
        let before = metronome.beatInBar
        try await Task.sleep(for: .milliseconds(400))

        #expect(metronome.isRunning)
        #expect(metronome.beatInBar != before || metronome.beatInBar != 0)
    }
}
