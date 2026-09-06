import AVFoundation
import Foundation
import Testing
@testable import Vigil

/// The factory notes start from silence and end at full level, so looping the raw file drops
/// to a hole and clicks back in. These measure the seam, not the code path.
@MainActor
@Suite("Seamless loop")
struct SeamlessLoopTests {

    private func rawNote(_ sound: String) throws -> AVAudioPCMBuffer {
        let catalog = FactoryCatalog()
        let path = try #require(catalog.padSounds[sound]?["C"])
        let url = try #require(catalog.url(for: path))
        let file = try AVAudioFile(forReading: url)
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: file.processingFormat,
                                                   frameCapacity: AVAudioFrameCount(file.length)))
        try file.read(into: buffer)
        return buffer
    }

    private func rms(_ buffer: AVAudioPCMBuffer, from: Int, to: Int) -> Float {
        let channel = buffer.floatChannelData![0]
        let lo = max(0, from), hi = min(Int(buffer.frameLength), to)
        guard hi > lo else { return 0 }
        var total: Float = 0
        for index in lo..<hi { total += channel[index] * channel[index] }
        return (total / Float(hi - lo)).squareRoot()
    }

    @Test("The raw file really does have the hole this fixes", arguments: ["Default", "Shimmer", "Synth"])
    func rawFileHasASeam(sound: String) throws {
        let raw = try rawNote(sound)
        let window = Int(0.05 * raw.format.sampleRate)
        let head = rms(raw, from: 0, to: window)
        let tail = rms(raw, from: Int(raw.frameLength) - window, to: Int(raw.frameLength))
        #expect(head < tail * 0.2, "\(sound): head \(head) is not far below tail \(tail)")
    }

    @Test("The looped buffer opens at playing level", arguments: ["Default", "Shimmer", "Synth"])
    func loopedBufferStartsLoud(sound: String) throws {
        let looped = try #require(SeamlessLoop.make(from: rawNote(sound)))
        let window = Int(0.05 * looped.format.sampleRate)
        let head = rms(looped, from: 0, to: window)
        let middle = rms(looped, from: Int(looped.frameLength) / 2 - window,
                         to: Int(looped.frameLength) / 2 + window)
        #expect(head > middle * 0.3, "\(sound): still opens quiet, \(head) against \(middle)")
    }

    @Test("The wrap does not jump", arguments: ["Default", "Shimmer", "Synth"])
    func wrapIsContinuous(sound: String) throws {
        let raw = try rawNote(sound)
        let looped = try #require(SeamlessLoop.make(from: raw))

        let rawChannel = raw.floatChannelData![0]
        let rawJump = abs(rawChannel[Int(raw.frameLength) - 1] - rawChannel[0])

        let channel = looped.floatChannelData![0]
        let jump = abs(channel[Int(looped.frameLength) - 1] - channel[0])

        #expect(jump < rawJump, "\(sound): wrap still jumps \(jump), raw was \(rawJump)")
        #expect(jump < 0.05, "\(sound): wrap jumps \(jump)")
    }

    @Test("The loop is shorter by exactly the crossfade")
    func lengthDropsByTheFade() throws {
        let raw = try rawNote("Default")
        let looped = try #require(SeamlessLoop.make(from: raw))
        let fadeFrames = Int(SeamlessLoop.fade * raw.format.sampleRate)
        #expect(Int(looped.frameLength) == Int(raw.frameLength) - fadeFrames)
    }

    @Test("A buffer with no room to fold is left alone")
    func tinyBufferIsRejected() throws {
        let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1))
        let tiny = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 2))
        tiny.frameLength = 2
        #expect(SeamlessLoop.make(from: tiny) == nil)
    }

    @Test("A short buffer still folds by a quarter of its length")
    func shortBufferFoldsProportionally() throws {
        let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1))
        let short = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 400))
        short.frameLength = 400
        let folded = try #require(SeamlessLoop.make(from: short))
        #expect(folded.frameLength == 300, "the fade is capped at a quarter of the buffer")
    }
}
