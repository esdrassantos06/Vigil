import Foundation
import Observation

struct FactorySlot: Hashable, Sendable {
    let name: String
    let file: String
}

struct FactoryKit: Identifiable, Hashable, Sendable {
    let id: String
    var name: String { Self.displayNames[id] ?? id }
    let slots: [FactorySlot]

    private static let displayNames = [
        "DrumKit1": "Drum Kit 1",
        "EFX1": "EFX 1",
        "WorshipDrums": "Worship Drums",
        "WorshipEFX": "Worship EFX",
    ]
}

struct PadSoundInfo: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let icon: String
}

/// Factory sounds shipped in the bundle, indexed by `Audio/manifest.json`.
@MainActor
@Observable
final class FactoryCatalog {
    private(set) var kits: [FactoryKit] = []
    private(set) var padSounds: [String: [String: String]] = [:]
    private(set) var padSoundList: [PadSoundInfo] = []
    private(set) var clicks: [String: String] = [:]

    private struct Manifest: Decodable {
        struct Slot: Decodable { let name: String; let file: String }
        let padSounds: [String: [String: String]]
        let kits: [String: [Slot]]
        let clicks: [String: String]
    }

    init() { load() }

    func url(for relativePath: String) -> URL? {
        Bundle.main.resourceURL?
            .appendingPathComponent("Audio")
            .appendingPathComponent(relativePath)
    }

    func kit(id: String) -> FactoryKit? {
        kits.first { $0.id == id }
    }

    func padSound(id: String) -> PadSoundInfo? {
        padSoundList.first { $0.id == id }
    }

    private static let padSoundOrder: [PadSoundInfo] = [
        PadSoundInfo(id: "Default", name: "Pad 1 (Padrão)", icon: "slider.horizontal.3"),
        PadSoundInfo(id: "Shimmer", name: "Pad Shimmer", icon: "sparkles"),
        PadSoundInfo(id: "Shimmer2", name: "Pad Shimmer 2", icon: "sparkles"),
        PadSoundInfo(id: "Analog", name: "Analog Pad", icon: "music.note"),
        PadSoundInfo(id: "Dark", name: "Dark Pad", icon: "moon"),
        PadSoundInfo(id: "Abba", name: "Abba Pad", icon: "music.note"),
        PadSoundInfo(id: "Reverse", name: "Pad Reverse", icon: "arrow.counterclockwise.circle"),
        PadSoundInfo(id: "Synth", name: "Pad Synth", icon: "waveform"),
    ]

    private func load() {
        guard let manifestURL = Bundle.main.url(
            forResource: "manifest",
            withExtension: "json",
            subdirectory: "Audio"
        ),
        let data = try? Data(contentsOf: manifestURL),
        let manifest = try? JSONDecoder().decode(Manifest.self, from: data)
        else { return }

        kits = manifest.kits
            .map { FactoryKit(id: $0.key, slots: $0.value.map { FactorySlot(name: $0.name, file: $0.file) }) }
            .sorted { $0.id < $1.id }
        padSounds = manifest.padSounds
        padSoundList = Self.padSoundOrder.filter { manifest.padSounds[$0.id] != nil }
        clicks = manifest.clicks
    }
}
