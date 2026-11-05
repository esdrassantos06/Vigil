import AVFoundation
#if os(macOS)
import CoreAudio
#endif

/// The app's only `AVAudioEngine`. Never build a second one.
final class AudioGraph {
    let engine = AVAudioEngine()

    /// 128 frames at 44.1kHz is about 2.9ms; the user can raise it in Settings if audio drops.
    static let defaultBufferFrames = 128
    private let sampleRate: Double = 44_100

    var mixer: AVAudioMixerNode { engine.mainMixerNode }

    /// Sits between the main mixer and the output, so every sound moves together.
    private let delay = AVAudioUnitDelay()

    /// Seconds added to everything Vigil plays; zero bypasses the unit.
    var outputDelay: Double = 0 {
        didSet {
            delay.delayTime = min(max(outputDelay, 0), 2)
            delay.bypass = outputDelay <= 0
        }
    }

    /// Set when the audio session refused to configure. The app would open silent, so this
    /// has to reach the user rather than sit in a log.
    private(set) var setupFailure: (any VigilError)?

    /// - Parameter preparesImmediately: false leaves the engine uninitialized, which is what
    ///   `enableManualRenderingMode` needs. It refuses to run on a prepared engine.
    init(preparesImmediately: Bool = true) {
        configureLowLatencyIO()
        // `prepare()` before any node exists fails inside AVAudioEngineGraph::Initialize.
        _ = engine.mainMixerNode
        delay.feedback = 0
        delay.wetDryMix = 100
        delay.lowPassCutoff = 20_000
        delay.delayTime = 0
        delay.bypass = true
        engine.attach(delay)
        engine.connect(engine.mainMixerNode, to: delay, format: nil)
        engine.connect(delay, to: engine.outputNode, format: nil)
        if preparesImmediately { engine.prepare() }
    }

    func start() throws {
        guard !engine.isRunning else { return }
        try engine.start()
        #if os(macOS)
        muteHardwareUnderTests()
        #endif
    }

    func attach(_ node: AVAudioNode, format: AVAudioFormat?) {
        engine.attach(node)
        engine.connect(node, to: mixer, format: format)
    }

    private func configureLowLatencyIO() {
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .default)
        } catch {
            setupFailure = AudioSessionError.sessionUnavailable
        }
        // Preferred values are hints. The system may keep its own and still play, so a
        // refusal here costs latency, not sound, and stays quiet.
        try? session.setPreferredSampleRate(sampleRate)
        try? session.setPreferredIOBufferDuration(Double(Self.defaultBufferFrames) / sampleRate)
        do {
            try session.setActive(true)
        } catch {
            setupFailure = AudioSessionError.sessionUnavailable
        }
        #elseif os(macOS)
        // Set while the graph is built, before anything renders: the same value from every
        // graph is then a no-op, while changing it later reconfigures engines already running.
        if let device = AudioOutput.defaultOutputID() {
            AudioOutput.setBufferFrames(Self.defaultBufferFrames, on: device)
        }
        #endif
    }

    /// Routes the engine to an output and asks it for a buffer size, then reads back what the
    /// hardware actually runs. Switching device restarts the engine, which stops what is playing.
    /// - Parameters:
    ///   - uid: the device to use, or nil for the system output.
    ///   - bufferFrames: the requested size, clamped to what the device accepts.
    /// - Returns: the buffer in use afterwards.
    /// - Throws: `OutputError.deviceMissing` when `uid` names no connected output.
    @discardableResult
    func applyOutput(uid: String?, bufferFrames: Int) throws -> ActiveBuffer? {
        #if os(macOS)
        let target: AudioDeviceID
        if let uid {
            guard let id = AudioOutput.deviceID(forUID: uid) else { throw OutputError.deviceMissing }
            target = id
        } else {
            guard let id = AudioOutput.defaultOutputID() else { return nil }
            target = id
        }
        if currentOutputID != target { try switchOutput(to: target) }
        let range = AudioOutput.bufferRange(of: target) ?? 15...4096
        AudioOutput.setBufferFrames(AudioOutput.clamp(bufferFrames, to: range), on: target)
        return ActiveBuffer(
            frames: AudioOutput.bufferFrames(of: target) ?? bufferFrames,
            sampleRate: AudioOutput.nominalSampleRate(of: target) ?? sampleRate
        )
        #else
        let session = AVAudioSession.sharedInstance()
        // A hint: the system may keep its own size, which the read-back then reports.
        try? session.setPreferredIOBufferDuration(Double(bufferFrames) / sampleRate)
        return ActiveBuffer(frames: Int((session.ioBufferDuration * session.sampleRate).rounded()),
                            sampleRate: session.sampleRate)
        #endif
    }

    #if os(macOS)
    /// The sizes the given output accepts, or every offered size when it cannot say.
    func bufferChoices(forUID uid: String?) -> [Int] {
        let device = uid.flatMap(AudioOutput.deviceID(forUID:)) ?? AudioOutput.defaultOutputID()
        guard let device, let range = AudioOutput.bufferRange(of: device) else { return AudioOutput.bufferChoices }
        return AudioOutput.bufferChoices.filter { range.contains($0) }
    }

    private var currentOutputID: AudioDeviceID? {
        guard let unit = engine.outputNode.audioUnit else { return nil }
        var id = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioUnitGetProperty(unit, kAudioOutputUnitProperty_CurrentDevice,
                                          kAudioUnitScope_Global, 0, &id, &size)
        return status == noErr ? id : nil
    }

    private func switchOutput(to device: AudioDeviceID) throws {
        guard let unit = engine.outputNode.audioUnit else { throw OutputError.deviceRefused }
        let wasRunning = engine.isRunning
        engine.stop()
        var id = device
        let status = AudioUnitSetProperty(unit, kAudioOutputUnitProperty_CurrentDevice,
                                          kAudioUnitScope_Global, 0, &id,
                                          UInt32(MemoryLayout<AudioDeviceID>.size))
        engine.prepare()
        if wasRunning { try engine.start() }
        muteHardwareUnderTests()
        guard status == noErr else { throw OutputError.deviceRefused }
    }

    /// The test scheme sets VIGIL_MUTE_OUTPUT so the suite's live engines stay off the
    /// speakers. Only the hardware output goes quiet: taps on the mixer and everything before
    /// it still see the full signal, and offline renders never reach this unit.
    private func muteHardwareUnderTests() {
        guard ProcessInfo.processInfo.environment["VIGIL_MUTE_OUTPUT"] == "1",
              let unit = engine.outputNode.audioUnit else { return }
        AudioUnitSetParameter(unit, kHALOutputParam_Volume, kAudioUnitScope_Global, 0, 0, 0)
    }
    #endif
}
