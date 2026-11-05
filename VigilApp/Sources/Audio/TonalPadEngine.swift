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

/// One timbre's players and decoded notes. The main sound and each stacked layer own one,
/// so a layer's fader is its mixer volume and moving it never restarts the loop.
@MainActor
private final class PadVoice {
    let mixer = AVAudioMixerNode()
    let players = [AVAudioPlayerNode(), AVAudioPlayerNode()]
    var activeSlot = 0
    var soundID: String?
    var buffers: [Note: AVAudioPCMBuffer] = [:]
    var warmTask: Task<Void, Never>?

    var idlePlayer: AVAudioPlayerNode { players[1 - activeSlot] }
}

/// One sustained note at a time, looped, crossfading on change. Every note is its own
/// file, so there is no pitch shifting. Up to three extra timbres can sound with the main one.
@MainActor
@Observable
final class TonalPadEngine {
    private(set) var activeNote: Note?
    private(set) var soundID: String = "Default"
    private(set) var layers: [PadLayer] = []

    var master: Double = 0.8 { didSet { mixer.outputVolume = Float(master) } }
    var pan: Double = 0 { didSet { mixer.pan = Float(pan) } }
    var crossfade: Double = 1.5

    /// Fader of the main timbre; the stacked layers carry their own in `layers`.
    var mainLevel: Double = 1 { didSet { voices[0].mixer.outputVolume = Float(mainLevel) } }

    var cutoff: Double = 12_000 { didSet { lowpass.frequency = Float(cutoff) } }
    var highpass: Double = 20 { didSet { highpassBand.frequency = Float(highpass) } }

    /// Shelf and bell gains in dB.
    var lowGain: Double = 0 { didSet { eq.bands[2].gain = Float(lowGain) } }
    var midGain: Double = 0 { didSet { eq.bands[3].gain = Float(midGain) } }
    var highGain: Double = 0 { didSet { eq.bands[4].gain = Float(highGain) } }

    var compressorEnabled = false { didSet { compressor.bypass = !compressorEnabled } }
    /// dB where compression starts.
    var compressorThreshold: Double = -20 {
        didSet { setCompressor(kDynamicsProcessorParam_Threshold, compressorThreshold) }
    }
    /// Make-up gain in dB after compression.
    var compressorGain: Double = 0 {
        didSet { setCompressor(kDynamicsProcessorParam_OverallGain, compressorGain) }
    }

    /// Wet share of the reverb, 0 to 1. At zero the unit is bypassed, so it costs nothing.
    var reverb: Double = 0 {
        didSet {
            reverbUnit.wetDryMix = Float(min(max(reverb, 0), 1) * 100)
            reverbUnit.bypass = reverb <= 0
        }
    }

    @ObservationIgnored private let graph: AudioGraph
    @ObservationIgnored private let catalog: FactoryCatalog
    @ObservationIgnored private let mixer = AVAudioMixerNode()
    @ObservationIgnored private let eq = AVAudioUnitEQ(numberOfBands: 5)
    @ObservationIgnored private let compressor = AVAudioUnitEffect(audioComponentDescription: AudioComponentDescription(
        componentType: kAudioUnitType_Effect,
        componentSubType: kAudioUnitSubType_DynamicsProcessor,
        componentManufacturer: kAudioUnitManufacturer_Apple,
        componentFlags: 0,
        componentFlagsMask: 0
    ))
    @ObservationIgnored private let pulseNode = PulseUnit.makeNode()
    @ObservationIgnored private let reverbUnit = AVAudioUnitReverb()
    @ObservationIgnored private let voices = (0...Settings.maxExtraLayers).map { _ in PadVoice() }
    @ObservationIgnored private var fadeTask: Task<Void, Never>?

    private var lowpass: AVAudioUnitEQFilterParameters { eq.bands[1] }
    private var highpassBand: AVAudioUnitEQFilterParameters { eq.bands[0] }

    /// Voices → pad mixer → filters and tone → compressor → pulse → reverb → main mixer.
    init(graph: AudioGraph, catalog: FactoryCatalog) {
        self.graph = graph
        self.catalog = catalog

        let format = graph.mixer.outputFormat(forBus: 0)
        let engine = graph.engine
        [mixer, eq, compressor, pulseNode, reverbUnit].forEach(engine.attach)
        reverbUnit.loadFactoryPreset(.cathedral)
        reverbUnit.wetDryMix = 0
        reverbUnit.bypass = true

        highpassBand.filterType = .highPass
        highpassBand.frequency = Float(highpass)
        highpassBand.bypass = false
        lowpass.filterType = .lowPass
        lowpass.frequency = Float(cutoff)
        lowpass.bypass = false
        let tone: [(AVAudioUnitEQFilterType, Float)] = [(.lowShelf, 150), (.parametric, 1_000), (.highShelf, 4_000)]
        for (offset, band) in tone.enumerated() {
            let parameters = eq.bands[offset + 2]
            parameters.filterType = band.0
            parameters.frequency = band.1
            parameters.bandwidth = 1.5
            parameters.gain = 0
            parameters.bypass = false
        }

        compressor.bypass = true
        setCompressor(kDynamicsProcessorParam_Threshold, compressorThreshold)
        setCompressor(kDynamicsProcessorParam_OverallGain, compressorGain)
        // ponytail: attack, release and headroom are fixed for a sustained pad; expose them if a sharper sound needs it.
        setCompressor(kDynamicsProcessorParam_HeadRoom, 5)
        setCompressor(kDynamicsProcessorParam_AttackTime, 0.01)
        setCompressor(kDynamicsProcessorParam_ReleaseTime, 0.3)

        for (index, voice) in voices.enumerated() {
            engine.attach(voice.mixer)
            for player in voice.players {
                engine.attach(player)
                engine.connect(player, to: voice.mixer, format: format)
                player.volume = 0
            }
            engine.connect(voice.mixer, to: mixer, fromBus: 0, toBus: AVAudioNodeBus(index), format: format)
            voice.mixer.outputVolume = index == 0 ? Float(mainLevel) : 0
        }
        voices[0].soundID = soundID

        engine.connect(mixer, to: eq, format: format)
        engine.connect(eq, to: compressor, format: format)
        engine.connect(compressor, to: pulseNode, format: format)
        engine.connect(pulseNode, to: reverbUnit, format: format)
        engine.connect(reverbUnit, to: graph.mixer, format: format)
        mixer.outputVolume = Float(master)
    }

    private func setCompressor(_ parameter: AudioUnitParameterID, _ value: Double) {
        AudioUnitSetParameter(compressor.audioUnit, parameter, kAudioUnitScope_Global, 0, AudioUnitParameterValue(value), 0)
    }

    /// The held note keeps sounding on its old buffer until the new one is decoded, so
    /// changing sound mid-note costs the main actor nothing.
    func selectSound(_ id: String) {
        soundID = id
        voices[0].soundID = id
        voices[0].buffers.removeAll()
        warm(voices[0], playing: activeNote)
    }

    /// Stacks up to three timbres on the main one. A level change only moves that layer's
    /// fader; a new timbre joins the held note once its buffer is decoded.
    func setLayers(_ requested: [PadLayer]) {
        let wanted = Array(requested.prefix(Settings.maxExtraLayers))
        guard wanted != layers else { return }
        var removedSound = false
        for (offset, voice) in voices.dropFirst().enumerated() {
            let layer = wanted[safe: offset]
            voice.mixer.outputVolume = Float(layer?.level ?? 0)
            guard voice.soundID != layer?.soundID else { continue }
            voice.soundID = layer?.soundID
            voice.buffers.removeAll()
            if layer == nil { removedSound = true } else { warm(voice, playing: activeNote) }
        }
        layers = wanted
        if removedSound, let activeNote { play(activeNote) }
    }

    /// Decodes every timbre's notes off the main actor so playing one never blocks the UI.
    /// Safe to call again: cached notes are skipped and an older pass is cancelled.
    /// - Parameter playing: decoded first and played as soon as it is ready.
    func warm(playing first: Note? = nil) {
        for voice in voices where voice.soundID != nil { warm(voice, playing: first) }
    }

    private func warm(_ voice: PadVoice, playing first: Note?) {
        voice.warmTask?.cancel()
        guard let sound = voice.soundID else { return }
        let order = first.map { held in [held] + Note.allCases.filter { $0 != held } } ?? Note.allCases
        voice.warmTask = Task { [weak self, weak voice] in
            for note in order {
                guard let self, let voice, !Task.isCancelled, voice.soundID == sound else { return }
                if voice.buffers[note] == nil, let url = url(for: note, sound: sound) {
                    await Task.yield()
                    guard let loaded = await Self.decode(url) else { continue }
                    guard !Task.isCancelled, voice.soundID == sound else { return }
                    voice.buffers[note] = loaded.buffer
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

    /// Tempo-synced volume shape on the pad. `shape == nil` turns it off.
    func setPulse(_ shape: PulseShape?, rate: PulseRate, depth: Double, bpm: Double) {
        (pulseNode.auAudioUnit as? PulseUnit)?.configure(shape: shape, rate: rate, depth: depth, bpm: bpm)
    }

    /// Lines the next pulse cycle up with a downbeat; called when the metronome starts.
    func resetPulsePhase() {
        (pulseNode.auAudioUnit as? PulseUnit)?.resetPhase()
    }

    func toggle(_ note: Note) {
        if activeNote == note { stop() } else { play(note) }
    }

    func play(_ note: Note) {
        var incoming: [AVAudioPlayerNode] = []
        for voice in voices {
            guard let buffer = buffer(for: note, in: voice) else { continue }
            let player = voice.idlePlayer
            player.stop()
            player.volume = 0
            player.scheduleBuffer(buffer, at: nil, options: .loops, completionHandler: nil)
            player.play()
            voice.activeSlot = 1 - voice.activeSlot
            incoming.append(player)
        }
        guard !incoming.isEmpty else { return }
        activeNote = note
        ramp(incoming: incoming, seconds: crossfade)
    }

    func stop() {
        activeNote = nil
        ramp(incoming: [], seconds: crossfade)
    }

    private func url(for note: Note, sound: String) -> URL? {
        guard let relative = catalog.padSounds[sound]?[note.rawValue] else { return nil }
        return catalog.url(for: relative)
    }

    /// Falls back to decoding inline when `warm()` has not reached this note yet.
    private func buffer(for note: Note, in voice: PadVoice) -> AVAudioPCMBuffer? {
        if let cached = voice.buffers[note] { return cached }
        guard let sound = voice.soundID, let url = url(for: note, sound: sound),
              let buffer = try? AVAudioPCMBuffer.contents(of: url)
        else { return nil }

        let looped = SeamlessLoop.make(from: buffer) ?? buffer
        voice.buffers[note] = looped
        return looped
    }

    /// Equal-power ramp, authoritative over **every** player: anything not in `incoming`
    /// falls to zero and is stopped at the end. A cancelled ramp leaves partial volumes, so each
    /// ramp starts from each node's current volume; without that an interrupted player loops forever.
    /// Progress follows the clock, not a step count, so a busy main actor delays a step but
    /// never stretches the fade.
    private func ramp(incoming: [AVAudioPlayerNode], seconds: Double) {
        fadeTask?.cancel()

        let fading = voices.flatMap(\.players).filter { player in !incoming.contains { $0 === player } }
        let startVolumes = fading.map(\.volume)
        let startIncoming = incoming.map(\.volume)
        let steps = CrossfadeCurve.steps(forFadeOf: seconds)
        let stepNanos = UInt64(seconds / Double(steps) * 1_000_000_000)
        let started = ContinuousClock.now

        fadeTask = Task {
            var progress = 0.0
            while progress < 1 {
                guard !Task.isCancelled else { return }
                let elapsed = started.duration(to: .now)
                progress = seconds > 0
                    ? min(1, (Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18) / seconds)
                    : 1
                let (rise, fall) = CrossfadeCurve.gains(at: progress)

                for (node, start) in zip(incoming, startIncoming) {
                    node.volume = max(start, rise)
                }
                for (node, start) in zip(fading, startVolumes) {
                    node.volume = start * fall
                }
                if progress < 1 { try? await Task.sleep(nanoseconds: stepNanos) }
            }
            guard !Task.isCancelled else { return }

            for node in incoming { node.volume = 1 }
            for node in fading {
                node.volume = 0
                node.stop()
            }
        }
    }
}
