import AVFoundation
import Foundation
import Testing
@testable import Vigil

/// Sample-accurate timing, measured on the rendered signal rather than on the clock.
@MainActor
@Suite("Metronome grid", .serialized)
struct OfflineMetronomeTests {

    private func render(bpm: Double, signature: TimeSignature = .fourFour, seconds: Double)
        throws -> (intervals: [Double], onsets: Int, expected: Double) {
        let graph = AudioGraph(preparesImmediately: false)
        let metronome = MetronomeEngine(graph: graph, catalog: FactoryCatalog())
        metronome.autoSchedules = false
        metronome.accentFirst = false
        metronome.bpm = bpm
        metronome.timeSignature = signature

        let captured = try OfflineRender.capture(
            graph,
            seconds: seconds,
            prepare: { metronome.start() },
            pump: { metronome.scheduleAhead() }
        )

        let positions = OfflineRender.onsets(in: captured.samples, rate: captured.sampleRate)
        let intervals = zip(positions.dropFirst(), positions).map {
            Double($0 - $1) / captured.sampleRate * 1000
        }
        let expected = 60_000 / bpm * (signature.beatUnit == 8 ? 0.5 : 1)
        return (intervals, positions.count, expected)
    }

    @Test("Clicks land on the grid at 128 BPM, the tempo where truncation used to drift")
    func gridAt128() throws {
        let result = try render(bpm: 128, seconds: 6)
        #expect(result.onsets >= 10, "expected several clicks, got \(result.onsets)")
        for interval in result.intervals {
            // Tolerance is the render block, 64 frames, which is the quantisation floor.
            #expect(abs(interval - result.expected) < 2,
                    "click off the grid: \(interval) ms, expected \(result.expected)")
        }
    }

    /// A minute of audio, because drift is cumulative and a short window hides it. Truncating
    /// samples per beat loses 0.875 of a sample here, which only adds up to something visible
    /// after a hundred beats.
    @Test("No accumulated drift over a minute at 128 BPM")
    func noAccumulatedDrift() throws {
        let result = try render(bpm: 128, seconds: 60)
        #expect(result.intervals.count > 100, "expected over 100 beats, got \(result.intervals.count)")

        let total = result.intervals.reduce(0, +)
        let ideal = result.expected * Double(result.intervals.count)
        #expect(abs(total - ideal) < 1.0, "accumulated \(abs(total - ideal)) ms of drift")
    }

    @Test("Eighth-note signatures click twice as often")
    func eighthNoteGrid() throws {
        let quarter = try render(bpm: 120, signature: .fourFour, seconds: 4)
        let eighth = try render(bpm: 120, signature: .sixEight, seconds: 4)
        #expect(eighth.onsets > quarter.onsets)
        for interval in eighth.intervals { #expect(abs(interval - 250) < 2) }
    }

    @Test("Double time halves the interval")
    func doubleTimeGrid() throws {
        let graph = AudioGraph(preparesImmediately: false)
        let metronome = MetronomeEngine(graph: graph, catalog: FactoryCatalog())
        metronome.autoSchedules = false
        metronome.accentFirst = false
        metronome.bpm = 120
        metronome.doubleTime = true

        let captured = try OfflineRender.capture(
            graph, seconds: 3,
            prepare: { metronome.start() },
            pump: { metronome.scheduleAhead() }
        )
        let positions = OfflineRender.onsets(in: captured.samples, rate: captured.sampleRate)
        let intervals = zip(positions.dropFirst(), positions).map {
            Double($0 - $1) / captured.sampleRate * 1000
        }
        #expect(!intervals.isEmpty)
        for interval in intervals { #expect(abs(interval - 250) < 2) }
    }
}
