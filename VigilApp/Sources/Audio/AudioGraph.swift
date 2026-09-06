import AVFoundation
#if os(macOS)
import CoreAudio
#endif

/// The app's only `AVAudioEngine`. Never build a second one.
final class AudioGraph {
    let engine = AVAudioEngine()

    /// 128 frames at 44.1kHz is about 2.9ms. Raise to 256 if the audio drops out.
    private let preferredFrames: UInt32 = 128
    private let sampleRate: Double = 44_100

    var mixer: AVAudioMixerNode { engine.mainMixerNode }

    /// - Parameter preparesImmediately: false leaves the engine uninitialized, which is what
    ///   `enableManualRenderingMode` needs. It refuses to run on a prepared engine.
    init(preparesImmediately: Bool = true) {
        configureLowLatencyIO()
        // `prepare()` before any node exists fails inside AVAudioEngineGraph::Initialize.
        _ = engine.mainMixerNode
        if preparesImmediately { engine.prepare() }
    }

    func start() throws {
        guard !engine.isRunning else { return }
        try engine.start()
    }

    func attach(_ node: AVAudioNode, format: AVAudioFormat?) {
        engine.attach(node)
        engine.connect(node, to: mixer, format: format)
    }

    func reconnect(_ node: AVAudioNode, format: AVAudioFormat) {
        engine.connect(node, to: mixer, format: format)
    }

    private func configureLowLatencyIO() {
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .default)
        try? session.setPreferredSampleRate(sampleRate)
        try? session.setPreferredIOBufferDuration(Double(preferredFrames) / sampleRate)
        try? session.setActive(true)
        #elseif os(macOS)
        setOutputBufferFrameSize(preferredFrames)
        #endif
    }

    #if os(macOS)
    /// On macOS the buffer size belongs to the output device, not to a session.
    private func setOutputBufferFrameSize(_ frames: UInt32) {
        var deviceAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var deviceID = AudioDeviceID(0)
        var deviceSize = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &deviceAddress, 0, nil, &deviceSize, &deviceID
        )
        guard status == noErr, deviceID != kAudioObjectUnknown else { return }

        var bufferAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyBufferFrameSize,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var value = frames
        AudioObjectSetPropertyData(
            deviceID, &bufferAddress, 0, nil, UInt32(MemoryLayout<UInt32>.size), &value
        )
    }
    #endif
}
