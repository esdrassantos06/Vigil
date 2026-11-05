import AudioToolbox
import AVFoundation

/// Tempo-synced volume shape applied to the tonal pad.
enum PulseShape: String, CaseIterable, Codable, Sendable {
    case pump, smooth, gate

    var label: String {
        switch self {
        case .pump: "Pump"
        case .smooth: "Suave"
        case .gate: "Gate"
        }
    }

    /// Gain for a cycle phase (0..<1): `(1 - depth) + depth * shape(phase)`.
    func gain(phase: Double, depth: Double) -> Double {
        guard depth > 0.0001 else { return 1 }
        let shaped: Double
        switch self {
        case .pump: shaped = min(max(pow(phase, 0.42), 0), 1)
        case .smooth: shaped = 0.5 - 0.5 * cos(2 * .pi * phase)
        case .gate: shaped = phase < 0.5 ? 1 : 0
        }
        return (1 - depth) + depth * shaped
    }
}

enum PulseRate: String, CaseIterable, Codable, Sendable {
    case quarter, eighth, eighthTriplet, sixteenth

    var cyclesPerBeat: Int {
        switch self {
        case .quarter: 1
        case .eighth: 2
        case .eighthTriplet: 3
        case .sixteenth: 4
        }
    }

    var label: String {
        switch self {
        case .quarter: "1/4"
        case .eighth: "1/8"
        case .eighthTriplet: "1/8T"
        case .sixteenth: "1/16"
        }
    }
}

/// Shared between the main actor, which writes the settings, and the render thread.
/// Plain aligned stores: a torn read costs at most one buffer of a stale value.
private struct PulseState {
    var shape: PulseShape?
    var depth = 0.0
    var cyclesPerSecond = 0.0
    var resetGeneration = 0
    var sampleRate = 44_100.0
    var phase = 0.0
    var gain = 1.0
    var seenGeneration = 0
}

/// In-process effect that multiplies its input by the pulse, sample by sample, on the render
/// thread. A UI timer would stutter whenever the main actor is busy, the way the metronome did.
final class PulseUnit: AUAudioUnit {
    static let componentDescription = AudioComponentDescription(
        componentType: kAudioUnitType_Effect,
        componentSubType: 0x7670_6C73,
        componentManufacturer: 0x5667_696C,
        componentFlags: 0,
        componentFlagsMask: 0
    )

    private static let registration: Void = {
        AUAudioUnit.registerSubclass(PulseUnit.self, as: componentDescription,
                                     name: "Vigil: Pulse", version: 1)
    }()

    /// An effect node wrapping a registered `PulseUnit`.
    static func makeNode() -> AVAudioUnitEffect {
        _ = registration
        return AVAudioUnitEffect(audioComponentDescription: componentDescription)
    }

    private let state = UnsafeMutablePointer<PulseState>.allocate(capacity: 1)
    private var inputs: AUAudioUnitBusArray!
    private var outputs: AUAudioUnitBusArray!

    override init(componentDescription: AudioComponentDescription,
                  options: AudioComponentInstantiationOptions = []) throws {
        state.initialize(to: PulseState())
        try super.init(componentDescription: componentDescription, options: options)
        let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 2)!
        inputs = AUAudioUnitBusArray(audioUnit: self, busType: .input, busses: [try AUAudioUnitBus(format: format)])
        outputs = AUAudioUnitBusArray(audioUnit: self, busType: .output, busses: [try AUAudioUnitBus(format: format)])
    }

    deinit {
        state.deinitialize(count: 1)
        state.deallocate()
    }

    override var inputBusses: AUAudioUnitBusArray { inputs }
    override var outputBusses: AUAudioUnitBusArray { outputs }
    override var canProcessInPlace: Bool { true }

    override func allocateRenderResources() throws {
        try super.allocateRenderResources()
        state.pointee.sampleRate = outputs[0].format.sampleRate
    }

    /// - Parameter shape: nil turns the pulse off.
    func configure(shape: PulseShape?, rate: PulseRate, depth: Double, bpm: Double) {
        state.pointee.shape = shape
        state.pointee.depth = shape == nil ? 0 : min(max(depth, 0), 1)
        state.pointee.cyclesPerSecond = max(bpm, 1) / 60 * Double(rate.cyclesPerBeat)
    }

    /// Starts the next cycle on the next render, so it lines up with a downbeat.
    func resetPhase() { state.pointee.resetGeneration &+= 1 }

    override var internalRenderBlock: AUInternalRenderBlock {
        let state = state
        return { _, timestamp, frameCount, _, outputData, _, pullInputBlock in
            guard let pullInputBlock else { return kAudioUnitErr_NoConnection }
            var flags = AudioUnitRenderActionFlags()
            let status = pullInputBlock(&flags, timestamp, frameCount, 0, outputData)
            guard status == noErr else { return status }

            var s = state.pointee
            if s.seenGeneration != s.resetGeneration {
                s.seenGeneration = s.resetGeneration
                s.phase = 0
            }
            guard let shape = s.shape else {
                state.pointee.phase = s.phase
                state.pointee.gain = 1
                state.pointee.seenGeneration = s.seenGeneration
                return noErr
            }

            let buffers = UnsafeMutableAudioBufferListPointer(outputData)
            let step = s.cyclesPerSecond / s.sampleRate
            let smoothing = 1 - exp(-1 / (0.002 * s.sampleRate))
            for frame in 0..<Int(frameCount) {
                s.gain += (shape.gain(phase: s.phase, depth: s.depth) - s.gain) * smoothing
                s.phase += step
                if s.phase >= 1 { s.phase -= s.phase.rounded(.down) }
                for buffer in buffers {
                    guard let data = buffer.mData?.assumingMemoryBound(to: Float.self) else { continue }
                    data[frame] *= Float(s.gain)
                }
            }
            state.pointee.phase = s.phase
            state.pointee.gain = s.gain
            state.pointee.seenGeneration = s.seenGeneration
            return noErr
        }
    }
}
