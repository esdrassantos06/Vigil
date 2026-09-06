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
}
