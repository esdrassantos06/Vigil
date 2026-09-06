import AVFoundation
import Foundation
import Testing
@testable import Vigil

/// Every knob on the tonal pad, measured on the rendered signal.
@MainActor
@Suite("Tonal pad controls", .serialized)
struct FilterTests {

    private struct Render {
        let left: [Float]
        let right: [Float]
        let rate: Double
    }

    /// The crossfade ramp is a `Task`, so the note is silent until the clock has moved.
    private func play(seconds: Double = 1.5, sound: String = "Default",
                      configure: (TonalPadEngine) -> Void) async throws -> Render {
        let graph = AudioGraph(preparesImmediately: false)
        let tonal = TonalPadEngine(graph: graph, catalog: FactoryCatalog())
        tonal.crossfade = 0.05
        tonal.selectSound(sound)
        configure(tonal)

        let captured = try await OfflineRender.capture(
            graph, seconds: seconds,
            settle: .milliseconds(200),
            prepare: { tonal.toggle(.C) },
            pump: {}
        )
        return Render(left: captured.samples, right: captured.right, rate: captured.sampleRate)
    }

    private func steady(_ samples: [Float]) -> [Float] {
        Array(samples.suffix(samples.count / 2))
    }

    @Test("The pad actually produces sound before anything is measured")
    func padSounds() async throws {
        let render = try await play { $0.master = 1 }
        #expect(OfflineRender.rms(steady(render.left)) > 0.001, "the pad rendered silence")
    }

    /// Shimmer is the brightest factory sound; on darker material the difference is small.
    @Test("Closing the cutoff removes high frequencies")
    func cutoffDarkens() async throws {
        let open = try await play(sound: "Shimmer") { $0.master = 1; $0.cutoff = Settings.cutoffRange.upperBound; $0.highpass = 20 }
        let closed = try await play(sound: "Shimmer") { $0.master = 1; $0.cutoff = Settings.cutoffRange.lowerBound; $0.highpass = 20 }

        let openBrightness = OfflineRender.brightness(steady(open.left))
        let closedBrightness = OfflineRender.brightness(steady(closed.left))
        #expect(closedBrightness < openBrightness * 0.95,
                "closed \(closedBrightness) is not darker than open \(openBrightness)")
    }

    @Test("Opening the high-pass removes low frequencies")
    func highPassThins() async throws {
        let full = try await play { $0.master = 1; $0.cutoff = Settings.cutoffRange.upperBound; $0.highpass = 20 }
        let thin = try await play { $0.master = 1; $0.cutoff = Settings.cutoffRange.upperBound; $0.highpass = Settings.highpassRange.upperBound }

        let fullWeight = OfflineRender.weight(steady(full.left))
        let thinWeight = OfflineRender.weight(steady(thin.left))
        #expect(thinWeight < fullWeight * 0.9,
                "high-passed \(thinWeight) is not lighter than full \(fullWeight)")
    }

    @Test("Pan moves the signal between the channels")
    func panMovesSides() async throws {
        let left = try await play { $0.master = 1; $0.pan = -1 }
        let right = try await play { $0.master = 1; $0.pan = 1 }

        let leftBias = OfflineRender.rms(steady(left.left)) / max(OfflineRender.rms(steady(left.right)), 0.00001)
        let rightBias = OfflineRender.rms(steady(right.right)) / max(OfflineRender.rms(steady(right.left)), 0.00001)
        #expect(leftBias > 2, "panning left did not favour the left channel (\(leftBias))")
        #expect(rightBias > 2, "panning right did not favour the right channel (\(rightBias))")
    }

    @Test("Centre pan keeps the channels level")
    func centrePanIsBalanced() async throws {
        let render = try await play { $0.master = 1; $0.pan = 0 }
        let leftLevel = OfflineRender.rms(steady(render.left))
        let rightLevel = OfflineRender.rms(steady(render.right))
        #expect(abs(leftLevel - rightLevel) < leftLevel * 0.1,
                "channels differ: \(leftLevel) against \(rightLevel)")
    }

    @Test("Master scales the output")
    func masterScales() async throws {
        let loud = try await play { $0.master = 1 }
        let quiet = try await play { $0.master = 0.25 }

        let loudLevel = OfflineRender.rms(steady(loud.left))
        let quietLevel = OfflineRender.rms(steady(quiet.left))
        #expect(quietLevel < loudLevel * 0.6,
                "master did not lower the level: \(quietLevel) against \(loudLevel)")
    }
}

@Suite("Crossfade steps")
struct CrossfadeStepTests {
    @Test("The shortest fade never jumps more than 5% of full scale in one step")
    func shortestFadeIsSmooth() {
        let seconds = Settings.crossfadeRange.lowerBound
        let count = CrossfadeCurve.steps(forFadeOf: seconds)
        let (rise, fall) = CrossfadeCurve.ramps(count: count)

        let jumps = zip(rise.dropFirst(), rise).map { abs($0 - $1) }
            + zip(fall.dropFirst(), fall).map { abs($0 - $1) }
        let worst = jumps.max() ?? 0
        #expect(worst < 0.05, "one step moves the gain by \(worst)")
    }

    @Test("A fade still takes at least one step")
    func neverZeroSteps() {
        #expect(CrossfadeCurve.steps(forFadeOf: 0) == 1)
    }
}
