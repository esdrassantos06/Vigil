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

/// Fills the click queue from outside the main actor, because the count has to keep going
/// while the UI is busy. Scheduling on `AVAudioPlayerNode` is thread safe and everything else
/// here is behind the lock, which is what the unchecked conformance rests on.
final class ClickScheduler: @unchecked Sendable {
    private let lock = NSLock()
    /// Held so the graph cannot be torn down while this can still schedule on its node.
    private let engine: AVAudioEngine
    private let player: AVAudioPlayerNode
    private let normal: AVAudioPCMBuffer
    private let accent: AVAudioPCMBuffer
    private let sampleRate: Double
    private let samplesPerBeat: Double
    private let beatsPerBar: Int
    private var accentFirst: Bool
    private var nextBeatSample: Double = 0
    private var beatCounter = 0

    init(engine: AVAudioEngine,
         player: AVAudioPlayerNode,
         normal: AVAudioPCMBuffer,
         accent: AVAudioPCMBuffer,
         sampleRate: Double,
         samplesPerBeat: Double,
         beatsPerBar: Int,
         accentFirst: Bool) {
        self.engine = engine
        self.player = player
        self.normal = normal
        self.accent = accent
        self.sampleRate = sampleRate
        self.samplesPerBeat = samplesPerBeat
        self.beatsPerBar = beatsPerBar
        self.accentFirst = accentFirst
    }

    /// `lastRenderTime` is node time and the player resets on every `play()`. Scheduling in
    /// node time throws the click far into the future and nothing sounds.
    static func playerSample(of player: AVAudioPlayerNode) -> AVAudioFramePosition? {
        guard let nodeTime = player.lastRenderTime,
              nodeTime.isSampleTimeValid || nodeTime.isHostTimeValid,
              let playerTime = player.playerTime(forNodeTime: nodeTime)
        else { return nil }
        return playerTime.sampleTime
    }

    /// Places beat zero. With no player clock yet the first click goes out immediately.
    /// - Returns: the sample the first beat sits on.
    func begin() -> Double {
        lock.withLock {
            guard let now = Self.playerSample(of: player) else {
                player.scheduleBuffer(accentFirst ? accent : normal, at: nil,
                                      options: [], completionHandler: nil)
                nextBeatSample = samplesPerBeat
                beatCounter = 1
                return 0
            }
            nextBeatSample = Double(now) + sampleRate * 0.1
            beatCounter = 0
            return nextBeatSample
        }
    }

    /// Toggling the accent must not restart the count, so it changes in place.
    func setAccentFirst(_ value: Bool) {
        lock.withLock { accentFirst = value }
    }

    func fill(horizonSeconds: Double) {
        lock.withLock {
            let now = Double(Self.playerSample(of: player) ?? 0)
            let horizon = now + sampleRate * horizonSeconds

            while nextBeatSample < horizon {
                let isDownbeat = beatCounter % beatsPerBar == 0
                let buffer = (accentFirst && isDownbeat) ? accent : normal
                let time = AVAudioTime(sampleTime: AVAudioFramePosition(nextBeatSample.rounded()),
                                       atRate: sampleRate)
                player.scheduleBuffer(buffer, at: time, options: [], completionHandler: nil)
                nextBeatSample += samplesPerBeat
                beatCounter += 1
            }
        }
    }
}

/// Scheduled ahead in `AVAudioTime` rather than off a UI timer, which drifts audibly.
@MainActor
@Observable
final class MetronomeEngine {
    private(set) var isRunning = false

    /// Which beat of the bar is sounding, from the player's own clock. Reading it off the
    /// scheduler instead would report how far the queue was filled, which is seconds ahead.
    var beatInBar: Int {
        guard isRunning, samplesPerBeat > 0,
              let now = ClickScheduler.playerSample(of: player) else { return 0 }
        let elapsed = Double(now) - firstBeatSample
        guard elapsed >= 0 else { return 0 }
        return Int(elapsed / samplesPerBeat) % timeSignature.beatsPerBar
    }

    var bpm: Double = 120 { didSet { restartIfRunning() } }
    var timeSignature: TimeSignature = .fourFour { didSet { restartIfRunning() } }
    var accentFirst = true { didSet { clicks?.setAccentFirst(accentFirst) } }
    var doubleTime = false { didSet { restartIfRunning() } }
    var volume: Double = 0.8 { didSet { player.volume = Float(volume) } }
    var pan: Double = 0 { didSet { player.pan = Float(pan) } }
    var sound: ClickSound = .logic { didSet { loadBuffers() } }

    @ObservationIgnored private let graph: AudioGraph
    @ObservationIgnored private let catalog: FactoryCatalog
    @ObservationIgnored private let player = AVAudioPlayerNode()
    @ObservationIgnored private(set) var normalBuffer: AVAudioPCMBuffer?
    @ObservationIgnored private(set) var accentBuffer: AVAudioPCMBuffer?
    @ObservationIgnored private var clicks: ClickScheduler?
    @ObservationIgnored private var pump: Task<Void, Never>?
    @ObservationIgnored private var firstBeatSample: Double = 0
    @ObservationIgnored private var tapTimes: [Date] = []

    var sampleRate: Double {
        graph.mixer.outputFormat(forBus: 0).sampleRate
    }

    var samplesPerBeat: Double {
        let effective = bpm * (doubleTime ? 2 : 1)
        let quarterSeconds = 60.0 / effective
        return sampleRate * quarterSeconds * (4.0 / Double(timeSignature.beatUnit))
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
        guard !isRunning, let normal = normalBuffer, let accent = accentBuffer else { return }
        isRunning = true
        player.play()

        let scheduler = ClickScheduler(
            engine: graph.engine,
            player: player,
            normal: normal,
            accent: accent,
            sampleRate: sampleRate,
            samplesPerBeat: samplesPerBeat,
            beatsPerBar: timeSignature.beatsPerBar,
            accentFirst: accentFirst
        )
        clicks = scheduler
        // The first bars are queued before any task exists, so nothing can leave the
        // downbeat silent.
        firstBeatSample = scheduler.begin()
        scheduler.fill(horizonSeconds: Self.scheduleHorizon)
        if autoSchedules { startPump(scheduler) }
    }

    /// Weakly held: an engine dropped without `stop()` has to end the pump, or it would keep
    /// scheduling on a graph nobody owns any more.
    private func startPump(_ scheduler: ClickScheduler) {
        pump = Task.detached(priority: .userInitiated) { [weak scheduler] in
            while !Task.isCancelled {
                guard let scheduler else { return }
                scheduler.fill(horizonSeconds: MetronomeEngine.scheduleHorizon)
                try? await Task.sleep(for: .milliseconds(50))
            }
        }
    }

    func stop() {
        isRunning = false
        pump?.cancel()
        pump = nil
        clicks = nil
        player.stop()
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

    /// How far ahead clicks are queued. The pump refills from a detached task, so this only
    /// has to outlast a scheduling hiccup, not a stalled main actor.
    nonisolated static let scheduleHorizon: Double = 2

    /// Offline rendering outruns the wall clock, so those tests pump this themselves.
    func scheduleAhead() {
        clicks?.fill(horizonSeconds: Self.scheduleHorizon)
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
