import AVFoundation
import Observation

/// Where a pad's sound comes from. Persisted alongside its colour and volume.
enum PadSource: Codable, Equatable, Hashable {
    case empty
    case custom(UUID)
    case native(kit: String, slot: Int)
}

/// One of the eight drum pads: playback node, preloaded buffer and visual identity.
@MainActor
@Observable
final class DrumPad: Identifiable {
    let id: Int
    var name: String?
    var color: PadColor
    var source: PadSource = .empty
    var volume: Double = 1.0 {
        didSet { applyGain() }
    }

    /// Drum master and the last trigger's velocity live here so gain has a single point of
    /// calculation: moving the slider must not drop the master.
    @ObservationIgnored var master: Double = 1.0 {
        didSet { applyGain() }
    }
    @ObservationIgnored var velocity: Double = 1.0

    func applyGain() {
        player.volume = Float(volume * master * velocity)
    }

    @ObservationIgnored let player = AVAudioPlayerNode()
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
            graph.attach(pad.player, format: format)
        }
    }

    func load(url: URL, into pad: DrumPad, name: String, source: PadSource) throws {
        let file = try AVAudioFile(forReading: url)
        let format = file.processingFormat
        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: AVAudioFrameCount(file.length)
        ) else {
            throw AudioError.bufferAllocationFailed
        }
        try file.read(into: buffer)

        graph.reconnect(pad.player, format: format)
        pad.buffer = buffer
        pad.name = name
        pad.source = source
    }

    /// - Parameter velocity: 0 to 1 from the Note On; keys and clicks fire at 1.
    func trigger(_ pad: DrumPad, velocity: Double = 1) {
        guard let buffer = pad.buffer else { return }
        pad.velocity = velocity
        pad.applyGain()
        if !pad.player.isPlaying { pad.player.play() }
        // .interrupts clears the queue and restarts in the same instant.
        // ponytail: one voice per pad; use a node pool if overlap is ever needed.
        pad.player.scheduleBuffer(buffer, at: nil, options: .interrupts, completionHandler: nil)
    }

    func stopAll() {
        for pad in pads { pad.player.stop() }
    }

    func clear(_ pad: DrumPad) {
        pad.player.stop()
        pad.buffer = nil
        pad.name = nil
        pad.source = .empty
    }

    private func applyMaster() {
        for pad in pads { pad.master = master }
    }

    private func applyPan() {
        for pad in pads { pad.player.pan = Float(pan) }
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
