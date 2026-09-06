import AVFoundation
import Foundation
@testable import Vigil

/// Renders the graph offline, sample by sample, with no wall clock involved.
///
/// - Parameter graph: the graph to render; its engine must not be running yet.
/// - Parameter seconds: how much audio to produce.
/// - Parameter pump: called after every rendered block, for whatever schedules ahead.
///
/// The block is deliberately small: a scheduled buffer can only start on a block boundary, so
/// the block size is the quantisation floor of any timing measured here.
/// - Returns: the absolute value of the left channel, one entry per frame.
@MainActor
enum OfflineRender {
    static func capture(
        _ graph: AudioGraph,
        seconds: Double,
        prepare: () -> Void,
        pump: () -> Void
    ) throws -> (samples: [Float], sampleRate: Double) {
        let engine = graph.engine
        let format = engine.mainMixerNode.outputFormat(forBus: 0)
        try engine.enableManualRenderingMode(.offline, format: format, maximumFrameCount: 64)
        try engine.start()
        prepare()

        guard let block = AVAudioPCMBuffer(
            pcmFormat: engine.manualRenderingFormat,
            frameCapacity: engine.manualRenderingMaximumFrameCount
        ) else { return ([], format.sampleRate) }

        let rate = engine.manualRenderingFormat.sampleRate
        let target = AVAudioFramePosition(seconds * rate)
        var samples: [Float] = []
        samples.reserveCapacity(Int(target))

        var stalled = 0
        while engine.manualRenderingSampleTime < target {
            pump()
            let before = engine.manualRenderingSampleTime
            let remaining = target - before
            let frames = AVAudioFrameCount(min(Int64(block.frameCapacity), remaining))
            let status = try engine.renderOffline(frames, to: block)
            guard status == .success, let channel = block.floatChannelData?[0] else { break }
            for index in 0..<Int(block.frameLength) { samples.append(abs(channel[index])) }

            // The render loop must always advance; bail instead of spinning forever.
            stalled = engine.manualRenderingSampleTime == before ? stalled + 1 : 0
            if stalled > 3 { break }
        }

        engine.stop()
        engine.disableManualRenderingMode()
        return (samples, rate)
    }

    /// Frame index of each attack. Re-arms only after the signal has been quiet for a while,
    /// so the decay of one click is not counted as the next.
    static func onsets(in samples: [Float], rate: Double, threshold: Float = 0.02) -> [Int] {
        let refractory = Int(0.08 * rate)
        let quiet = Int(0.02 * rate)
        var result: [Int] = []
        var index = 0
        while index < samples.count {
            guard samples[index] > threshold else { index += 1; continue }
            result.append(index)
            index += refractory
            var silence = 0
            while index < samples.count && silence < quiet {
                silence = samples[index] > threshold ? 0 : silence + 1
                index += 1
            }
        }
        return result
    }
}
