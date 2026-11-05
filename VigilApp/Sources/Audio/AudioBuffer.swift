import AVFoundation

extension AVAudioPCMBuffer {
    /// Reads a whole audio file into memory, keeping the file's own processing format.
    /// - Throws: `AudioError.bufferAllocationFailed`, or whatever `AVAudioFile` raises.
    static func contents(of url: URL) throws -> AVAudioPCMBuffer {
        let file = try AVAudioFile(forReading: url)
        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: file.processingFormat,
            frameCapacity: AVAudioFrameCount(file.length)
        ) else {
            throw AudioError.bufferAllocationFailed
        }
        try file.read(into: buffer)
        return buffer
    }

    /// A copy of `range` in this buffer's format; the buffer itself when it covers everything.
    func slice(_ range: Range<Int>) -> AVAudioPCMBuffer? {
        guard range != 0..<Int(frameLength) else { return self }
        guard !range.isEmpty, range.upperBound <= Int(frameLength),
              let source = floatChannelData,
              let copy = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(range.count)),
              let destination = copy.floatChannelData
        else { return nil }
        copy.frameLength = AVAudioFrameCount(range.count)
        for channel in 0..<Int(format.channelCount) {
            memcpy(destination[channel], source[channel] + range.lowerBound, range.count * MemoryLayout<Float>.size)
        }
        return copy
    }
}
