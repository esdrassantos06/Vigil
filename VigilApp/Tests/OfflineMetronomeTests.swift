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

/// Which buffer landed on which beat, read off the rendered signal.
///
/// Loudness is the wrong metric: the accent is a different timbre, not a louder one, and its
/// peak measures the same. So the clicks are compared by shape instead.
@MainActor
@Suite("Metronome accent", .serialized)
struct OfflineAccentTests {

    /// One short window of samples per click.
    private func clickShapes(accentFirst: Bool) throws -> [[Float]] {
        let graph = AudioGraph(preparesImmediately: false)
        let metronome = MetronomeEngine(graph: graph, catalog: FactoryCatalog())
        metronome.autoSchedules = false
        metronome.bpm = 240
        metronome.timeSignature = .fourFour
        metronome.accentFirst = accentFirst

        let captured = try OfflineRender.capture(
            graph, seconds: 4,
            prepare: { metronome.start() },
            pump: { metronome.scheduleAhead() }
        )

        let window = Int(0.03 * captured.sampleRate)
        return OfflineRender.onsets(in: captured.samples, rate: captured.sampleRate)
            .compactMap { start in
                guard start + window <= captured.samples.count else { return nil }
                return Array(captured.samples[start..<(start + window)])
            }
    }

    /// Mean absolute difference, so two renders of the same buffer score near zero.
    private func distance(_ a: [Float], _ b: [Float]) -> Float {
        let count = min(a.count, b.count)
        guard count > 0 else { return 0 }
        var total: Float = 0
        for index in 0..<count { total += abs(a[index] - b[index]) }
        return total / Float(count)
    }

    @Test("With the accent off, every click is the same waveform")
    func unaccentedClicksMatch() throws {
        let shapes = try clickShapes(accentFirst: false)
        #expect(shapes.count >= 8, "expected several clicks, got \(shapes.count)")

        let reference = try #require(shapes.first)
        for shape in shapes.dropFirst() {
            #expect(distance(shape, reference) < 0.001, "clicks differ with the accent off")
        }
    }

    @Test("With the accent on, one click in four is a different waveform")
    func accentedBarHasOneOddClick() throws {
        let shapes = try clickShapes(accentFirst: true)
        #expect(shapes.count >= 8, "expected several clicks, got \(shapes.count)")

        // The plain click is whatever most beats look like, so take the shape closest to
        // its neighbours as the reference.
        let reference = try #require(shapes.min { left, right in
            let leftScore = shapes.map { distance($0, left) }.reduce(0, +)
            let rightScore = shapes.map { distance($0, right) }.reduce(0, +)
            return leftScore < rightScore
        })

        let odd = shapes.filter { distance($0, reference) > 0.001 }.count
        let bars = shapes.count / 4
        #expect(odd > 0, "no accented click found; the accent buffer never played")
        #expect(abs(odd - bars) <= 1, "\(odd) accented clicks across \(shapes.count) beats")
    }
}
