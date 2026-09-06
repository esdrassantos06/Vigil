import AVFoundation
import Foundation
@testable import Vigil

/// Taps the mixer to measure the signal that actually leaves it. Normal engine mode, not
/// manual rendering: the metronome scheduler runs off the wall clock.
final class AudioCapture: @unchecked Sendable {
    private let lock = NSLock()
    private var samples: [Float] = []
    private var sampleRate: Double = 44_100

    func attach(to graph: AudioGraph) {
        let node = graph.engine.mainMixerNode
        let format = node.outputFormat(forBus: 0)
        sampleRate = format.sampleRate
        node.installTap(onBus: 0, bufferSize: 1_024, format: format) { [weak self] (buffer: AVAudioPCMBuffer, _: AVAudioTime) in
            guard let self, let channel = buffer.floatChannelData?[0] else { return }
            let frames = Int(buffer.frameLength)
            var chunk = [Float](repeating: 0, count: frames)
            for index in 0..<frames { chunk[index] = abs(channel[index]) }
            lock.lock()
            samples.append(contentsOf: chunk)
            lock.unlock()
        }
    }

    func detach(from graph: AudioGraph) {
        graph.engine.mainMixerNode.removeTap(onBus: 0)
    }

    var rate: Double { sampleRate }

    func onsets(threshold: Float = 0.02, refractory: Double = 0.05) -> [Int] {
        lock.lock()
        let captured = samples
        lock.unlock()

        let gap = Int(refractory * sampleRate)
        var result: [Int] = []
        var index = 0
        while index < captured.count {
            if captured[index] > threshold {
                result.append(index)
                index += gap
            } else {
                index += 1
            }
        }
        return result
    }

    func intervalsMs() -> [Double] {
        let positions = onsets()
        guard positions.count > 1 else { return [] }
        return zip(positions.dropFirst(), positions).map {
            Double($0 - $1) / sampleRate * 1000
        }
    }

    var isSilent: Bool {
        lock.lock()
        defer { lock.unlock() }
        return samples.allSatisfy { $0 < 0.001 }
    }
}
