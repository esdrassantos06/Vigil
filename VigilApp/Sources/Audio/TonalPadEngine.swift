import AVFoundation
import Observation

enum Note: String, CaseIterable, Codable, Sendable {
    case C, Cs, D, Ds, E, F, Fs, G, Gs, A, As, B

    func label(sharps: Bool, major: Bool = true) -> String {
        guard major else {
            let relative = Note.allCases[(index + 9) % 12]
            return relative.name(sharps: sharps) + "m"
        }
        return name(sharps: sharps)
    }

    private var index: Int { Note.allCases.firstIndex(of: self) ?? 0 }

    private func name(sharps: Bool) -> String {
        guard rawValue.hasSuffix("s") else { return rawValue }
        let root = String(rawValue.dropLast())
        if sharps { return root + "#" }
        let flats = ["C": "Db", "D": "Eb", "F": "Gb", "G": "Ab", "A": "Bb"]
        return flats[root] ?? root + "#"
    }
}

enum SeamlessLoop {
    static let fade: Double = 2.0

    static func make(from source: AVAudioPCMBuffer, fadeSeconds: Double = fade) -> AVAudioPCMBuffer? {
        let total = Int(source.frameLength)
        let fadeFrames = min(Int(fadeSeconds * source.format.sampleRate), total / 4)
        guard fadeFrames > 0, total > fadeFrames * 2,
              let input = source.floatChannelData,
              let output = AVAudioPCMBuffer(pcmFormat: source.format,
                                            frameCapacity: AVAudioFrameCount(total - fadeFrames))
        else { return nil }

        let length = total - fadeFrames
        output.frameLength = AVAudioFrameCount(length)
        guard let destination = output.floatChannelData else { return nil }

        for channel in 0..<Int(source.format.channelCount) {
            let from = input[channel], to = destination[channel]
            for index in 0..<fadeFrames {
                let (rise, fall) = CrossfadeCurve.gains(at: Double(index) / Double(fadeFrames))
                to[index] = from[index] * rise + from[length + index] * fall
            }
            for index in fadeFrames..<length { to[index] = from[index] }
        }
        return output
    }
}

/// Equal-power crossfade: the two gains keep constant energy, so the transition has no dip
/// in the middle the way a linear fade does.
enum CrossfadeCurve {
    static func gains(at progress: Double) -> (rise: Float, fall: Float) {
        let clamped = min(1, max(0, progress))
        return (Float(sin(clamped * .pi / 2)), Float(cos(clamped * .pi / 2)))
    }
}

/// One sustained note at a time, looped, crossfading on change. Every note is its own
/// file, so there is no pitch shifting.
@MainActor
@Observable
final class TonalPadEngine {
    private(set) var activeNote: Note?
    private(set) var soundID: String = "Default"

    var master: Double = 0.8 { didSet { mixer.outputVolume = Float(master) } }
    var pan: Double = 0 { didSet { mixer.pan = Float(pan) } }
    var crossfade: Double = 1.5

    var cutoff: Double = 12_000 { didSet { lowpass.frequency = Float(cutoff) } }
    var highpass: Double = 20 { didSet { highpassBand.frequency = Float(highpass) } }

    @ObservationIgnored private let graph: AudioGraph
    @ObservationIgnored private let catalog: FactoryCatalog
    @ObservationIgnored private let mixer = AVAudioMixerNode()
    @ObservationIgnored private let eq = AVAudioUnitEQ(numberOfBands: 2)
    @ObservationIgnored private let players = [AVAudioPlayerNode(), AVAudioPlayerNode()]
    @ObservationIgnored private var activeSlot = 0
    @ObservationIgnored private var fadeTask: Task<Void, Never>?
    @ObservationIgnored private var buffers: [Note: AVAudioPCMBuffer] = [:]

    private var lowpass: AVAudioUnitEQFilterParameters { eq.bands[1] }
    private var highpassBand: AVAudioUnitEQFilterParameters { eq.bands[0] }

    init(graph: AudioGraph, catalog: FactoryCatalog) {
        self.graph = graph
        self.catalog = catalog

        let format = graph.mixer.outputFormat(forBus: 0)
        graph.engine.attach(mixer)
        graph.engine.attach(eq)
        for player in players { graph.engine.attach(player) }

        highpassBand.filterType = .highPass
        highpassBand.frequency = Float(highpass)
        highpassBand.bypass = false
        lowpass.filterType = .lowPass
        lowpass.frequency = Float(cutoff)
        lowpass.bypass = false

        for player in players {
            graph.engine.connect(player, to: mixer, format: format)
            player.volume = 0
        }
        graph.engine.connect(mixer, to: eq, format: format)
        graph.engine.connect(eq, to: graph.mixer, format: format)
        mixer.outputVolume = Float(master)
    }

    func selectSound(_ id: String) {
        soundID = id
        buffers.removeAll()
        if let note = activeNote {
            play(note)
        }
    }

    func toggle(_ note: Note) {
        if activeNote == note { stop() } else { play(note) }
    }

    func play(_ note: Note) {
        guard let buffer = buffer(for: note) else { return }

        let incoming = players[1 - activeSlot]

        incoming.stop()
        incoming.volume = 0
        incoming.scheduleBuffer(buffer, at: nil, options: .loops, completionHandler: nil)
        incoming.play()

        activeSlot = 1 - activeSlot
        activeNote = note
        ramp(incoming: incoming, seconds: crossfade)
    }

    func stop() {
        activeNote = nil
        ramp(incoming: nil, seconds: crossfade)
    }

    private func buffer(for note: Note) -> AVAudioPCMBuffer? {
        if let cached = buffers[note] { return cached }
        guard let relative = catalog.padSounds[soundID]?[note.rawValue],
              let url = catalog.url(for: relative),
              let file = try? AVAudioFile(forReading: url),
              let buffer = AVAudioPCMBuffer(
                pcmFormat: file.processingFormat,
                frameCapacity: AVAudioFrameCount(file.length)
              ),
              (try? file.read(into: buffer)) != nil
        else { return nil }

        let looped = SeamlessLoop.make(from: buffer) ?? buffer
        buffers[note] = looped
        return looped
    }

    /// Equal-power ramp, authoritative over **every** player: anything that is not `incoming`
    /// falls to zero and is stopped at the end. A cancelled ramp leaves partial volumes, so each
    /// ramp starts from each node's current volume; without that an interrupted player loops forever.
    /// ponytail: ~60fps steps; move to sample-accurate automation if it ever clicks.
    private func ramp(incoming: AVAudioPlayerNode?, seconds: Double) {
        fadeTask?.cancel()

        let fading = players.filter { $0 !== incoming }
        let startVolumes = fading.map(\.volume)
        let startIncoming = incoming?.volume ?? 0
        let steps = max(1, Int(seconds * 60))
        let stepNanos = UInt64(seconds / Double(steps) * 1_000_000_000)

        fadeTask = Task {
            for step in 1...steps {
                guard !Task.isCancelled else { return }
                let progress = Double(step) / Double(steps)
                let (rise, fall) = CrossfadeCurve.gains(at: progress)

                incoming?.volume = max(startIncoming, rise)
                for (node, start) in zip(fading, startVolumes) {
                    node.volume = start * fall
                }
                try? await Task.sleep(nanoseconds: stepNanos)
            }
            guard !Task.isCancelled else { return }

            incoming?.volume = 1
            for node in fading {
                node.volume = 0
                node.stop()
            }
        }
    }
}
