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

    @ObservationIgnored var buffer: AVAudioPCMBuffer?

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

    @ObservationIgnored private let graph: AudioGraph

    init(graph: AudioGraph) {
        self.graph = graph
        let palette = PadColor.allCases
        pads = (0..<8).map { DrumPad(id: $0, color: palette[$0 % palette.count]) }
        let format = graph.mixer.outputFormat(forBus: 0)
        for pad in pads {
            for voice in pad.voices { graph.attach(voice, format: format) }
        }
    }

    func load(url: URL, into pad: DrumPad, name: String, source: PadSource) throws {
        let buffer = try AVAudioPCMBuffer.contents(of: url)

        for voice in pad.voices { graph.reconnect(voice, format: buffer.format) }
        pad.buffer = buffer
        pad.name = name
        pad.source = source
    }

    /// - Parameter velocity: 0 to 1 from the Note On; keys and clicks fire at 1.
    func trigger(_ pad: DrumPad, velocity: Double = 1) {
        guard let buffer = pad.buffer else { return }
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

enum AudioError: VigilError {
    case bufferAllocationFailed

    var messageKey: String.LocalizationValue {
        switch self {
        case .bufferAllocationFailed: "Não foi possível carregar o áudio."
        }
    }
}
