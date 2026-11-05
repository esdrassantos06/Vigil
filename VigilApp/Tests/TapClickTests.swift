import AVFoundation
import Foundation
import Testing
@testable import Vigil

/// Tapping the tempo sounds the chosen click, so the performer hears the taps land. Measured
/// on the rendered signal.
@MainActor
@Suite("Tap click", .serialized)
struct TapClickTests {

    private func render(running: Bool) async throws -> Int {
        let graph = AudioGraph(preparesImmediately: false)
        let metronome = MetronomeEngine(graph: graph, catalog: FactoryCatalog())
        metronome.autoSchedules = false
        metronome.bpm = 30
        let captured = try await OfflineRender.capture(
            graph,
            seconds: 1,
            prepare: {
                if running { metronome.start() }
                metronome.tap()
            },
            pump: { metronome.scheduleAhead() }
        )
        return OfflineRender.onsets(in: captured.samples, rate: captured.sampleRate).count
    }

    @Test("A tap with the metronome stopped plays one click")
    func tapClicks() async throws {
        #expect(try await render(running: false) == 1)
    }

    @Test("A tap while the metronome runs adds no click of its own")
    func noDoubleClickWhileRunning() async throws {
        #expect(try await render(running: true) == 1, "only the metronome's downbeat in the first second at 30 BPM")
    }
}
