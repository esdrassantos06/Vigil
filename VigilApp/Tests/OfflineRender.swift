import AVFoundation
import Foundation
@testable import Vigil

@MainActor
enum OfflineRender {
    /// - Parameter settle: real time to wait before rendering. Anything driven by a `Task`,
    ///   like the crossfade ramp, needs the clock to move before it has set any volume.
    ///
    /// The render block is small on purpose: a scheduled buffer can only start on a block
    /// boundary, so the block size is the floor of any timing measured here.
    static func capture(
        _ graph: AudioGraph,
        seconds: Double,
        settle: Duration = .zero,
        prepare: () -> Void,
        pump: () -> Void
    ) async throws -> (samples: [Float], right: [Float], sampleRate: Double) {
        let engine = graph.engine
        let format = engine.mainMixerNode.outputFormat(forBus: 0)
        try engine.enableManualRenderingMode(.offline, format: format, maximumFrameCount: 64)
        try engine.start()
        prepare()
        if settle > .zero { try? await Task.sleep(for: settle) }

        guard let block = AVAudioPCMBuffer(
            pcmFormat: engine.manualRenderingFormat,
            frameCapacity: engine.manualRenderingMaximumFrameCount
        ) else { return ([], [], format.sampleRate) }

        let rate = engine.manualRenderingFormat.sampleRate
        let target = AVAudioFramePosition(seconds * rate)
        var samples: [Float] = []
        var right: [Float] = []
        samples.reserveCapacity(Int(target))
        right.reserveCapacity(Int(target))

        var stalled = 0
        while engine.manualRenderingSampleTime < target {
            pump()
            let before = engine.manualRenderingSampleTime
            let remaining = target - before
            let frames = AVAudioFrameCount(min(Int64(block.frameCapacity), remaining))
            let status = try engine.renderOffline(frames, to: block)
            guard status == .success, let channels = block.floatChannelData else { break }
            let hasRight = block.format.channelCount > 1
            for index in 0..<Int(block.frameLength) {
                samples.append(channels[0][index])
                right.append(hasRight ? channels[1][index] : channels[0][index])
            }

            stalled = engine.manualRenderingSampleTime == before ? stalled + 1 : 0
            if stalled > 3 { break }
        }

        engine.stop()
        engine.disableManualRenderingMode()
        return (samples, right, rate)
    }

    /// High-frequency content, divided by level so it does not move with volume.
    static func brightness(_ samples: [Float]) -> Float {
        guard samples.count > 1 else { return 0 }
        var total: Float = 0
        for index in 1..<samples.count { total += abs(samples[index] - samples[index - 1]) }
        let level = rms(samples)
        guard level > 0 else { return 0 }
        return total / Float(samples.count - 1) / level
    }

    /// Low-frequency content, also level independent.
    static func weight(_ samples: [Float], window: Int = 64) -> Float {
        guard samples.count > window else { return 0 }
        var running: Float = 0
        for index in 0..<window { running += samples[index] }
        var total: Float = 0
        for index in window..<samples.count {
            running += samples[index] - samples[index - window]
            total += abs(running / Float(window))
        }
        let level = rms(samples)
        guard level > 0 else { return 0 }
        return total / Float(samples.count - window) / level
    }

    static func rms(_ samples: [Float]) -> Float {
        guard !samples.isEmpty else { return 0 }
        let sum = samples.reduce(Float(0)) { $0 + $1 * $1 }
        return (sum / Float(samples.count)).squareRoot()
    }

    static func onsets(in samples: [Float], rate: Double, threshold: Float = 0.02) -> [Int] {
        let refractory = Int(0.08 * rate)
        let quiet = Int(0.02 * rate)
        var result: [Int] = []
        var index = 0
        while index < samples.count {
            guard abs(samples[index]) > threshold else { index += 1; continue }
            result.append(index)
            index += refractory
            var silence = 0
            while index < samples.count && silence < quiet {
                silence = abs(samples[index]) > threshold ? 0 : silence + 1
                index += 1
            }
        }
        return result
    }
}
