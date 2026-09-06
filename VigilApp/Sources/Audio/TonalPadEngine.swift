import Accelerate
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

    /// vDSP rather than a per-sample loop: a 40s stereo pad is about two million frames per
    /// channel, and the scalar version blocked the main actor for ~370ms on every cold note.
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

        let (rise, fall) = CrossfadeCurve.ramps(count: fadeFrames)
        let tail = length - fadeFrames

        for channel in 0..<Int(source.format.channelCount) {
            let from = input[channel], to = destination[channel]
            vDSP_vmul(from, 1, rise, 1, to, 1, vDSP_Length(fadeFrames))
            vDSP_vma(from + length, 1, fall, 1, to, 1, to, 1, vDSP_Length(fadeFrames))
            memcpy(to + fadeFrames, from + fadeFrames, tail * MemoryLayout<Float>.size)
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

    /// The same curve sampled `count` times, for the vectorised crossfade.
    /// Steps a fade of `seconds` should take. A player node applies volume once per render
    /// buffer (128 frames, about 3ms), so this is as fine as the API resolves; coarser steps
    /// leave an audible jump on the shortest fade, where 60 a second means 13% of full scale.
    static func steps(forFadeOf seconds: Double) -> Int {
        max(1, Int(seconds * 300))
    }

    static func ramps(count: Int) -> (rise: [Float], fall: [Float]) {
        var rise = [Float](repeating: 0, count: count)
        var fall = [Float](repeating: 0, count: count)
        for index in 0..<count {
            let (up, down) = gains(at: Double(index) / Double(count))
            rise[index] = up
            fall[index] = down
        }
        return (rise, fall)
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
    @ObservationIgnored private var warmTask: Task<Void, Never>?
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

    /// The held note keeps sounding on its old buffer until the new one is decoded, so
    /// changing sound mid-note costs the main actor nothing.
    func selectSound(_ id: String) {
        soundID = id
        buffers.removeAll()
        warm(playing: activeNote)
    }

    /// Decodes the current sound's notes off the main actor so playing one never blocks the
    /// UI. Safe to call again: cached notes are skipped and an older pass is cancelled.
    /// - Parameter playing: decoded first and played as soon as it is ready.
    func warm(playing first: Note? = nil) {
        warmTask?.cancel()
        let sound = soundID
        let order = first.map { held in [held] + Note.allCases.filter { $0 != held } } ?? Note.allCases
        warmTask = Task { [weak self] in
            for note in order {
                guard let self, !Task.isCancelled, soundID == sound else { return }
                if buffers[note] == nil, let url = url(for: note) {
                    await Task.yield()
                    guard let loaded = await Self.decode(url) else { continue }
                    guard !Task.isCancelled, soundID == sound else { return }
                    buffers[note] = loaded.buffer
                }
                if note == first, activeNote == first { play(note) }
            }
        }
    }

    /// The buffer is built inside the task and handed over untouched, so nothing else can
    /// reach it while it crosses back to the main actor.
    private struct Loaded: @unchecked Sendable {
        let buffer: AVAudioPCMBuffer
    }

    private static func decode(_ url: URL) async -> Loaded? {
        await Task.detached(priority: .background) {
            guard let raw = try? AVAudioPCMBuffer.contents(of: url) else { return nil }
            return Loaded(buffer: SeamlessLoop.make(from: raw) ?? raw)
        }.value
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

    private func url(for note: Note) -> URL? {
        guard let relative = catalog.padSounds[soundID]?[note.rawValue] else { return nil }
        return catalog.url(for: relative)
    }

    /// Falls back to decoding inline when `warm()` has not reached this note yet.
    private func buffer(for note: Note) -> AVAudioPCMBuffer? {
        if let cached = buffers[note] { return cached }
        guard let url = url(for: note),
              let buffer = try? AVAudioPCMBuffer.contents(of: url)
        else { return nil }

        let looped = SeamlessLoop.make(from: buffer) ?? buffer
        buffers[note] = looped
        return looped
    }

    /// Equal-power ramp, authoritative over **every** player: anything that is not `incoming`
    /// falls to zero and is stopped at the end. A cancelled ramp leaves partial volumes, so each
    /// ramp starts from each node's current volume; without that an interrupted player loops forever.
    private func ramp(incoming: AVAudioPlayerNode?, seconds: Double) {
        fadeTask?.cancel()

        let fading = players.filter { $0 !== incoming }
        let startVolumes = fading.map(\.volume)
        let startIncoming = incoming?.volume ?? 0
        let steps = CrossfadeCurve.steps(forFadeOf: seconds)
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
