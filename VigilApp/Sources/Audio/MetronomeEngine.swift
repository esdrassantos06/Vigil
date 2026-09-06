import AVFoundation
import Observation

enum TimeSignature: String, CaseIterable, Codable, Sendable {
    case threeFour = "3/4"
    case fourFour = "4/4"
    case fiveFour = "5/4"
    case sixEight = "6/8"
    case sevenEight = "7/8"
    case twelveEight = "12/8"

    var beatsPerBar: Int {
        switch self {
        case .threeFour: 3
        case .fourFour: 4
        case .fiveFour: 5
        case .sixEight: 6
        case .sevenEight: 7
        case .twelveEight: 12
        }
    }

    var beatUnit: Int {
        switch self {
        case .threeFour, .fourFour, .fiveFour: 4
        case .sixEight, .sevenEight, .twelveEight: 8
        }
    }
}

enum ClickSound: String, CaseIterable, Codable, Sendable {
    case logic, classic, cowbell, blip

    var label: String {
        switch self {
        case .logic: "Logic"
        case .classic: "Classic"
        case .cowbell: "Cowbell"
        case .blip: "Blip"
        }
    }

    var keys: (normal: String, accent: String) {
        switch self {
        case .logic: ("click_logic", "click_logic_accent")
        case .classic: ("Classic", "Classic_Accent")
        case .cowbell: ("Cowbell", "Cowbell_Accent")
        case .blip: ("Blip", "Blip_accent")
        }
    }
}

/// Scheduled ahead in `AVAudioTime` rather than off a UI timer, which drifts audibly.
@MainActor
@Observable
final class MetronomeEngine {
    private(set) var isRunning = false
    private(set) var beatInBar = 0

    var bpm: Double = 120 { didSet { restartIfRunning() } }
    var timeSignature: TimeSignature = .fourFour { didSet { restartIfRunning() } }
    var accentFirst = true
    var doubleTime = false { didSet { restartIfRunning() } }
    var volume: Double = 0.8 { didSet { player.volume = Float(volume) } }
    var pan: Double = 0 { didSet { player.pan = Float(pan) } }
    var sound: ClickSound = .logic { didSet { loadBuffers() } }

    @ObservationIgnored private let graph: AudioGraph
    @ObservationIgnored private let catalog: FactoryCatalog
    @ObservationIgnored private let player = AVAudioPlayerNode()
    @ObservationIgnored private(set) var normalBuffer: AVAudioPCMBuffer?
    @ObservationIgnored private(set) var accentBuffer: AVAudioPCMBuffer?
    @ObservationIgnored private var scheduler: Task<Void, Never>?
    /// Double accumulator: truncating samples per beat costs about 76ms of drift over half
    /// an hour at 128 BPM. Rounding happens only when scheduling.
    @ObservationIgnored private var nextBeatSample: Double = 0
    @ObservationIgnored private var beatCounter = 0
    @ObservationIgnored private var tapTimes: [Date] = []

    var sampleRate: Double {
        graph.mixer.outputFormat(forBus: 0).sampleRate
    }

    var samplesPerBeat: Double {
        let effective = bpm * (doubleTime ? 2 : 1)
        let quarterSeconds = 60.0 / effective
        return sampleRate * quarterSeconds * (4.0 / Double(timeSignature.beatUnit))
    }

    /// `lastRenderTime` is node time and the player resets on every `play()`. Scheduling in
    /// node time throws the click far into the future and nothing sounds.
    private func currentPlayerSample() -> AVAudioFramePosition? {
        guard let nodeTime = player.lastRenderTime,
              nodeTime.isSampleTimeValid || nodeTime.isHostTimeValid,
              let playerTime = player.playerTime(forNodeTime: nodeTime)
        else { return nil }
        return playerTime.sampleTime
    }

    init(graph: AudioGraph, catalog: FactoryCatalog) {
        self.graph = graph
        self.catalog = catalog
        graph.attach(player, format: graph.mixer.outputFormat(forBus: 0))
        player.volume = Float(volume)
        loadBuffers()
    }

    /// When false the caller pumps `scheduleAhead()` itself. Offline rendering runs faster
    /// than real time, so the wall-clock scheduler would fall behind.
    var autoSchedules = true

    func toggle() { isRunning ? stop() : start() }

    func start() {
        guard !isRunning, normalBuffer != nil else { return }
        isRunning = true
        beatCounter = 0
        beatInBar = 0
        player.play()

        guard let now = currentPlayerSample() else {
            if let first = accentFirst ? accentBuffer : normalBuffer {
                player.scheduleBuffer(first, at: nil, options: [], completionHandler: nil)
            }
            nextBeatSample = samplesPerBeat
            beatCounter = 1
            if autoSchedules { startScheduler() }
            return
        }
        nextBeatSample = Double(now) + sampleRate * 0.1

        if autoSchedules { startScheduler() }
    }

    private func startScheduler() {
        scheduler = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, self.isRunning else { return }
                self.scheduleAhead()
                try? await Task.sleep(for: .milliseconds(50))
            }
        }
    }

    func stop() {
        isRunning = false
        scheduler?.cancel()
        scheduler = nil
        player.stop()
        beatInBar = 0
    }

    func tap() {
        let now = Date()
        tapTimes.append(now)
        tapTimes = tapTimes.filter { now.timeIntervalSince($0) < 3 }
        guard tapTimes.count >= 2 else { return }

        let intervals = zip(tapTimes.dropFirst(), tapTimes).map { $0.timeIntervalSince($1) }
        let average = intervals.reduce(0, +) / Double(intervals.count)
        guard average > 0 else { return }
        bpm = min(300, max(20, (60.0 / average).rounded()))
    }

    func scheduleAhead() {
        guard let normal = normalBuffer, let accent = accentBuffer else { return }
        let now = Double(currentPlayerSample() ?? 0)
        let horizon = now + sampleRate * 0.3

        while nextBeatSample < horizon {
            let isDownbeat = beatCounter % timeSignature.beatsPerBar == 0
            let buffer = (accentFirst && isDownbeat) ? accent : normal
            let time = AVAudioTime(sampleTime: AVAudioFramePosition(nextBeatSample.rounded()), atRate: sampleRate)

            player.scheduleBuffer(buffer, at: time, options: [], completionHandler: nil)

            nextBeatSample += samplesPerBeat
            beatCounter += 1
            beatInBar = beatCounter % timeSignature.beatsPerBar
        }
    }

    private func restartIfRunning() {
        guard isRunning else { return }
        stop()
        start()
    }

    private func loadBuffers() {
        normalBuffer = buffer(forKey: sound.keys.normal)
        accentBuffer = buffer(forKey: sound.keys.accent) ?? normalBuffer
    }

    /// The clicks ship at different rates (`click_logic` 48k, its accent 44.1k) and share one
    /// node. Without converting on load the buffer will not match the connection and stays silent.
    private func buffer(forKey key: String) -> AVAudioPCMBuffer? {
        guard let relative = catalog.clicks[key],
              let url = catalog.url(for: relative),
              let source = try? AVAudioPCMBuffer.contents(of: url)
        else { return nil }

        return convert(source, to: graph.mixer.outputFormat(forBus: 0))
    }

    private func convert(_ source: AVAudioPCMBuffer, to target: AVAudioFormat) -> AVAudioPCMBuffer? {
        if source.format == target { return source }
        guard let converter = AVAudioConverter(from: source.format, to: target) else { return nil }

        let ratio = target.sampleRate / source.format.sampleRate
        let capacity = AVAudioFrameCount(Double(source.frameLength) * ratio) + 4096
        guard let output = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else { return nil }

        var delivered = false
        var error: NSError?
        converter.convert(to: output, error: &error) { _, status in
            if delivered {
                status.pointee = .noDataNow
                return nil
            }
            delivered = true
            status.pointee = .haveData
            return source
        }
        return error == nil ? output : nil
    }
}
