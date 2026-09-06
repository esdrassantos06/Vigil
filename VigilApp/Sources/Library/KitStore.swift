import Foundation
import Observation

struct StoredSlot: Codable, Equatable, Sendable {
    var source: PadSource
    var color: PadColor
    var volume: Double
    var voicing: PadVoicing

    init(source: PadSource, color: PadColor, volume: Double, voicing: PadVoicing = .poly) {
        self.source = source
        self.color = color
        self.volume = volume
        self.voicing = voicing
    }

    /// Slots written before the play mode existed load as overlapping, which is what they did.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        source = try container.decode(PadSource.self, forKey: .source)
        color = try container.decode(PadColor.self, forKey: .color)
        volume = try container.decode(Double.self, forKey: .volume)
        voicing = try container.decodeIfPresent(PadVoicing.self, forKey: .voicing) ?? .poly
    }
}

struct UserKit: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    var name: String
    var slots: [StoredSlot]
}

/// Factory kits are read only; editing one produces a user copy.
enum KitRef: Codable, Equatable, Sendable {
    case factory(String)
    case user(UUID)
}

@MainActor
@Observable
final class KitStore {
    private(set) var kits: [UserKit] = []

    @ObservationIgnored private let key = "userKits"
    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        restore()
    }

    func kit(id: UUID) -> UserKit? {
        kits.first { $0.id == id }
    }

    @discardableResult
    func save(name: String, slots: [StoredSlot]) -> UserKit {
        let kit = UserKit(id: UUID(), name: name, slots: slots)
        kits.append(kit)
        persist()
        return kit
    }

    func update(id: UUID, slots: [StoredSlot]) {
        guard let index = kits.firstIndex(where: { $0.id == id }), kits[index].slots != slots else { return }
        kits[index].slots = slots
        persist()
    }

    func rename(_ kit: UserKit, to name: String) {
        guard let index = kits.firstIndex(where: { $0.id == kit.id }) else { return }
        kits[index].name = name
        persist()
    }

    func delete(_ kit: UserKit) {
        kits.removeAll { $0.id == kit.id }
        persist()
    }

    private func persist() {
        defaults.store(kits, forKey: key)
    }

    private func restore() {
        guard let decoded = defaults.decoded([UserKit].self, forKey: key) else { return }
        kits = decoded
    }
}
