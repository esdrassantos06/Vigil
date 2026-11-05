import Foundation
import Observation

enum MidiTarget: Hashable, Sendable {
    case tonal(Note)
    case drum(Int)
    case stop
    case padMaster, cutoff, highpass, padReverb, pulseDepth
    case drumMaster
    case drumVolume(Int)
    case metronomeVolume, metronomeToggle, tapTempo

    var key: String {
        switch self {
        case .tonal(let note): "tonal.\(note.rawValue)"
        case .drum(let index): "drum.\(index)"
        case .stop: "stop"
        case .padMaster: "padMaster"
        case .cutoff: "cutoff"
        case .highpass: "highpass"
        case .padReverb: "padReverb"
        case .pulseDepth: "pulseDepth"
        case .drumMaster: "drumMaster"
        case .drumVolume(let index): "drumVolume.\(index)"
        case .metronomeVolume: "metronomeVolume"
        case .metronomeToggle: "metronomeToggle"
        case .tapTempo: "tapTempo"
        }
    }

    var label: String {
        switch self {
        case .tonal(let note): note.label(sharps: true)
        case .drum(let index): "Pad \(index + 1)"
        case .stop: "Stop"
        case .padMaster: "Volume Master (Pad)"
        case .cutoff: "Cutoff (Pad)"
        case .highpass: "Passa-alta (Pad)"
        case .padReverb: "Reverb (Pad)"
        case .pulseDepth: "Pulse (Pad)"
        case .drumMaster: "Master (Drum)"
        case .drumVolume(let index): "Volume (Drum Pad \(index + 1))"
        case .metronomeVolume: "Volume (Metrônomo)"
        case .metronomeToggle: "Iniciar (Play/Pause)"
        case .tapTempo: "Tap Tempo"
        }
    }

    /// Default computer keys. Live and metronome targets have none.
    var defaultKey: String? {
        switch self {
        case .tonal(let note): Self.noteKeys[note]
        case .drum(let index): Self.drumKeys[safe: index]
        default: nil
        }
    }

    /// The MIDI note a fresh install maps to this target: C to B on 60 to 71, the drum pads on
    /// 36 to 43, where General MIDI and most controllers' drum pads sit.
    var defaultNote: UInt8? {
        switch self {
        case .tonal(let note): Note.allCases.firstIndex(of: note).map { UInt8(60 + $0) }
        case .drum(let index): (0..<8).contains(index) ? UInt8(36 + index) : nil
        default: nil
        }
    }

    private static let drumKeys = ["z", "x", "c", "v", "b", "n", "m", ","]

    private static let noteKeys: [Note: String] = [
        .C: "a", .Cs: "w", .D: "s", .Ds: "e", .E: "d", .F: "f",
        .Fs: "t", .G: "g", .Gs: "y", .A: "h", .As: "u", .B: "j",
    ]

    static let sections: [(title: String, targets: [MidiTarget])] = [
        ("Pads", Note.allCases.map { .tonal($0) }),
        ("Drum Pads", (0..<8).map { .drum($0) }),
        ("Live", [.stop, .padMaster, .cutoff, .highpass, .padReverb, .pulseDepth, .drumMaster]
            + (0..<8).map { .drumVolume($0) }),
        ("Metrônomo", [.metronomeVolume, .metronomeToggle, .tapTempo]),
    ]

    static let all: [MidiTarget] = sections.flatMap(\.targets)
}

enum MidiBinding: Hashable, Codable, Sendable {
    case note(UInt8)
    case cc(UInt8)
    case key(String)

    var label: String {
        switch self {
        case .note(let number): "Nota \(number)"
        case .cc(let number): "CC \(number)"
        case .key(let character): character.uppercased()
        }
    }

    var isKeyboard: Bool {
        if case .key = self { return true }
        return false
    }
}

@MainActor
@Observable
final class MidiConfig {
    private(set) var bindings: [String: [MidiBinding]] = Stored.defaults
    var channel = 1 { didSet { persist() } }
    var disabledInputs: Set<String> = [] { didSet { persist() } }

    @ObservationIgnored private var reverse: [MidiBinding: MidiTarget] = [:]
    @ObservationIgnored private let storageKey = "midiConfig"
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var isRestoring = false

    /// - Parameter defaults: injected so tests never touch the real preferences.
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        restore()
        indexBindings()
    }

    func bindings(for target: MidiTarget) -> [MidiBinding] { bindings[target.key] ?? [] }

    func binding(for target: MidiTarget, keyboard: Bool) -> MidiBinding? {
        bindings(for: target).first { $0.isKeyboard == keyboard }
    }
    func target(for binding: MidiBinding) -> MidiTarget? { reverse[binding] }

    /// The computer key printed on a control, or nil when the target has none.
    func keyHint(for target: MidiTarget) -> String? {
        binding(for: target, keyboard: true)?.label
    }

    /// Replaces only the shortcut of the same kind, and takes it from whoever held it.
    /// - Parameter binding: the captured key, note or CC.
    /// - Parameter target: the target that will respond to it.
    func set(_ binding: MidiBinding, for target: MidiTarget) {
        for (key, list) in bindings {
            let kept = list.filter { $0 != binding }
            if kept.count != list.count { bindings[key] = kept.isEmpty ? nil : kept }
        }
        var list = (bindings[target.key] ?? []).filter { $0.isKeyboard != binding.isKeyboard }
        list.append(binding)
        bindings[target.key] = list
        commit()
    }

    func clear(_ target: MidiTarget) {
        bindings[target.key] = nil
        commit()
    }

    func clear(_ target: MidiTarget, keyboard: Bool) {
        let kept = bindings(for: target).filter { $0.isKeyboard != keyboard }
        bindings[target.key] = kept.isEmpty ? nil : kept
        commit()
    }

    func clearAll() {
        bindings = [:]
        commit()
    }

    /// Puts back the default computer key and MIDI note of every target. Learned CCs stay.
    func restoreDefaults() {
        let defaults = Stored.defaults
        let taken = Set(defaults.values.joined())
        for target in MidiTarget.all {
            let kept = bindings(for: target).filter { if case .cc = $0 { !taken.contains($0) } else { false } }
            let list = kept + (defaults[target.key] ?? [])
            bindings[target.key] = list.isEmpty ? nil : list
        }
        commit()
    }

    private func commit() {
        indexBindings()
        persist()
    }

    private func indexBindings() {
        var index: [MidiBinding: MidiTarget] = [:]
        for target in MidiTarget.all {
            for binding in bindings[target.key] ?? [] { index[binding] = target }
        }
        reverse = index
    }

    private struct Stored: Codable {
        var channel: Int
        var disabledInputs: [String]
        var bindings: [String: [MidiBinding]]

        static let defaults: [String: [MidiBinding]] = {
            var map: [String: [MidiBinding]] = [:]
            for target in MidiTarget.all {
                let list = [target.defaultKey.map { MidiBinding.key($0) },
                            target.defaultNote.map { MidiBinding.note($0) }].compactMap { $0 }
                if !list.isEmpty { map[target.key] = list }
            }
            return map
        }()
    }

    private func persist() {
        guard !isRestoring else { return }
        let stored = Stored(
            channel: channel,
            disabledInputs: Array(disabledInputs),
            bindings: bindings
        )
        defaults.store(stored, forKey: storageKey)
    }

    private func restore() {
        isRestoring = true
        defer { isRestoring = false }
        guard let stored = defaults.decoded(Stored.self, forKey: storageKey) else { return }
        channel = stored.channel
        disabledInputs = Set(stored.disabledInputs)
        bindings = stored.bindings
    }
}
