import AVFoundation
import Observation

/// Where a pad's sound comes from. Persisted alongside its colour and volume.
enum PadSource: Codable, Equatable, Hashable {
    case empty
    case custom(UUID)
    case native(kit: String, slot: Int)
}

/// How a pad answers a hit while its previous one still sounds. Named after a drum
/// program's play mode: `poly` lets the tails stack, `mono` restarts the sound.
enum PadVoicing: String, Codable, Sendable {
    case poly, mono
}

/// The part of a one-shot a pad plays, as fractions of its length.
enum PadTrim {
    static let full: ClosedRange<Double> = 0...1

    /// Start stops at 98% and the window never drops under 2%, so a pad is never silent.
    static func clamp(_ trim: ClosedRange<Double>) -> ClosedRange<Double> {
        let start = min(max(trim.lowerBound, 0), 0.98)
        return start...min(max(trim.upperBound, start + 0.02), 1)
    }

    static func frames(_ trim: ClosedRange<Double>, of count: Int) -> Range<Int> {
        guard count > 0 else { return 0..<0 }
        let window = clamp(trim)
        let first = min(Int((Double(count) * window.lowerBound).rounded()), count - 1)
        let last = min(max(first + 1, Int((Double(count) * window.upperBound).rounded())), count)
        return first..<last
    }
}

/// One of the eight drum pads: playback node, preloaded buffer and visual identity.
@MainActor
@Observable
final class DrumPad: Identifiable {
    let id: Int
    var name: String?
    var color: PadColor
    var source: PadSource = .empty
    var voicing: PadVoicing = .poly
    /// Lit for a moment after a trigger. It lives here, not on the model, so a hit
    /// re-renders one pad rather than every view that reads the model.
    var isFlashing = false
    var volume: Double = 1.0 {
        didSet { applyGain() }
    }

    /// Drum master lives here so gain has a single point of calculation: moving the slider
    /// must not drop the master.
    @ObservationIgnored var master: Double = 1.0 {
        didSet { applyGain() }
    }

    /// Share of this pad sent to the drum reverb, 0 to 1.
    var reverbSend: Double = 0 {
        didSet { send.outputVolume = Float(reverbSend) }
    }

    /// Feeds the drum reverb. A mixer per pad because `AVAudioMixingDestination.volume` on a
    /// fanned-out player is not honoured: a send of zero still reached the reverb at full level.
    @ObservationIgnored let send = AVAudioMixerNode()

    /// One node per simultaneous hit: a retrigger takes the next voice, so the tail of the
    /// previous one keeps ringing instead of being cut mid-decay. Voices are taken in order,
    /// so a ninth hit reuses the oldest, whose tail has decayed the most.
    @ObservationIgnored let voices = (0..<8).map { _ in AVAudioPlayerNode() }
    @ObservationIgnored private var nextVoice = 0
    @ObservationIgnored private var velocities = [Double](repeating: 1, count: 8)

    /// Each voice keeps the velocity of the hit that started it, so an older tail is not
    /// relevelled by a softer hit landing on top of it.
    func applyGain() {
        for (index, voice) in voices.enumerated() {
            voice.volume = Float(volume * master * velocities[index])
        }
    }

    /// - Returns: the node the next hit should play on.
    func claimVoice(velocity: Double) -> AVAudioPlayerNode {
        let index = nextVoice
        nextVoice = (nextVoice + 1) % voices.count
        velocities[index] = velocity
        applyGain()
        return voices[index]
    }

    var trim: ClosedRange<Double> = PadTrim.full { didSet { cutPlayBuffer() } }

    @ObservationIgnored var buffer: AVAudioPCMBuffer? { didSet { cutPlayBuffer() } }

    /// `buffer` cut to `trim`, cut once here so a hit never copies audio.
    @ObservationIgnored private(set) var playBuffer: AVAudioPCMBuffer?

    private func cutPlayBuffer() {
        guard let buffer else { playBuffer = nil; return }
        playBuffer = buffer.slice(PadTrim.frames(trim, of: Int(buffer.frameLength))) ?? buffer
    }

    /// Derived from `source`, which is observed. `buffer` is `@ObservationIgnored` and would
    /// never re-render the UI.
    var isAssigned: Bool { source != .empty }

    init(id: Int, color: PadColor) {
        self.id = id
        self.color = color
    }

    var label: String { "D\(id + 1)" }
}

/// The eight drum pads. One-shots with immediate retrigger and a global hard stop.
@MainActor
@Observable
final class DrumEngine {
    private(set) var pads: [DrumPad]
    var master: Double = 1.0 { didSet { applyMaster() } }
    var pan: Double = 0 { didSet { applyPan() } }

    var highpass: Double = 20 {
        didSet {
            filter.bands[0].frequency = Float(highpass)
            filter.bands[0].bypass = highpass <= Settings.highpassRange.lowerBound
        }
    }

    var cutoff: Double = 20_000 {
        didSet {
            filter.bands[1].frequency = Float(cutoff)
            filter.bands[1].bypass = cutoff >= Settings.drumCutoffRange.upperBound
        }
    }

    var reverbPreset: DrumReverb = .mediumHall {
        didSet { if reverbPreset != oldValue { reverb.loadFactoryPreset(reverbPreset.factoryPreset) } }
    }

    /// Return level of the reverb, applied before it so the room keeps its character.
    var reverbLevel: Double = 1 { didSet { sendMixer.outputVolume = Float(reverbLevel) } }

    @ObservationIgnored private let graph: AudioGraph
    @ObservationIgnored private let bus = AVAudioMixerNode()
    @ObservationIgnored private let sendMixer = AVAudioMixerNode()
    @ObservationIgnored private let reverb = AVAudioUnitReverb()
    @ObservationIgnored private let filter = AVAudioUnitEQ(numberOfBands: 2)

    /// Voices → drum bus and reverb send; reverb → drum bus; drum bus → filters → main mixer.
    init(graph: AudioGraph) {
        self.graph = graph
        let palette = PadColor.allCases
        pads = (0..<8).map { DrumPad(id: $0, color: palette[$0 % palette.count]) }
        let format = graph.mixer.outputFormat(forBus: 0)
        let engine = graph.engine
        [bus, sendMixer, reverb, filter].forEach(engine.attach)

        filter.bands[0].filterType = .highPass
        filter.bands[1].filterType = .lowPass
        for band in filter.bands { band.bypass = true }
        filter.bands[0].frequency = Float(highpass)
        filter.bands[1].frequency = Float(cutoff)
        reverb.loadFactoryPreset(reverbPreset.factoryPreset)
        reverb.wetDryMix = 100

        engine.connect(sendMixer, to: reverb, format: format)
        engine.connect(reverb, to: bus, fromBus: 0, toBus: Self.reverbReturnBus, format: format)
        engine.connect(bus, to: filter, format: format)
        engine.connect(filter, to: graph.mixer, format: format)

        for pad in pads {
            engine.attach(pad.send)
            engine.connect(pad.send, to: sendMixer, fromBus: 0, toBus: AVAudioNodeBus(pad.id), format: format)
            pad.send.outputVolume = Float(pad.reverbSend)
            for voice in pad.voices {
                engine.attach(voice)
                wire(voice, of: pad, format: format)
            }
        }
    }

    private static let reverbReturnBus: AVAudioNodeBus = 0

    /// Fixed buses: voice `n` of pad `p` lands on input `p * 8 + n + 1` of the drum bus, after
    /// the reverb return, and on input `n` of its pad's send.
    private func wire(_ voice: AVAudioPlayerNode, of pad: DrumPad, format: AVAudioFormat) {
        guard let index = pad.voices.firstIndex(where: { $0 === voice }) else { return }
        graph.engine.disconnectNodeOutput(voice)
        graph.engine.connect(voice, to: [
            AVAudioConnectionPoint(node: bus, bus: AVAudioNodeBus(pad.id * pad.voices.count + index + 1)),
            AVAudioConnectionPoint(node: pad.send, bus: AVAudioNodeBus(index)),
        ], fromBus: 0, format: format)
    }

    func load(url: URL, into pad: DrumPad, name: String, source: PadSource) throws {
        let buffer = try AVAudioPCMBuffer.contents(of: url)

        for voice in pad.voices { wire(voice, of: pad, format: buffer.format) }
        pad.trim = PadTrim.full
        pad.buffer = buffer
        pad.name = name
        pad.source = source
    }

    /// - Parameter velocity: 0 to 1 from the Note On; keys and clicks fire at 1.
    func trigger(_ pad: DrumPad, velocity: Double = 1) {
        guard let buffer = pad.playBuffer else { return }
        let voice = pad.claimVoice(velocity: velocity)
        if pad.voicing == .mono {
            for other in pad.voices where other !== voice { other.stop() }
        }
        if !voice.isPlaying { voice.play() }
        // .interrupts clears that voice's queue and restarts in the same instant.
        voice.scheduleBuffer(buffer, at: nil, options: .interrupts, completionHandler: nil)
    }

    func stopAll() {
        for pad in pads {
            for voice in pad.voices { voice.stop() }
        }
    }

    func clear(_ pad: DrumPad) {
        for voice in pad.voices { voice.stop() }
        pad.buffer = nil
        pad.name = nil
        pad.source = .empty
    }

    private func applyMaster() {
        for pad in pads { pad.master = master }
    }

    private func applyPan() {
        for pad in pads {
            for voice in pad.voices { voice.pan = Float(pan) }
        }
    }
}

extension DrumReverb {
    var factoryPreset: AVAudioUnitReverbPreset {
        switch self {
        case .smallRoom: .smallRoom
        case .mediumRoom: .mediumRoom
        case .mediumHall: .mediumHall
        case .largeHall: .largeHall
        case .plate: .plate
        case .cathedral: .cathedral
        }
    }
}

/// The output could not be prepared. On iOS this is the difference between playing and
/// opening silent, so it is an error the user sees.
enum AudioSessionError: VigilError {
    case sessionUnavailable

    var messageKey: String.LocalizationValue {
        switch self {
        case .sessionUnavailable: "Não foi possível preparar a saída de áudio. Pode não sair som."
        }
    }
}

enum AudioError: VigilError {
    case bufferAllocationFailed

    var messageKey: String.LocalizationValue {
        switch self {
        case .bufferAllocationFailed: "Não foi possível carregar o áudio."
        }
    }
}
