import Foundation
import Observation

struct StoredSlot: Codable, Equatable, Sendable {
    var source: PadSource
    var color: PadColor
    var volume: Double
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
        guard let data = try? JSONEncoder().encode(kits) else { return }
        defaults.set(data, forKey: key)
    }

    private func restore() {
        guard let data = defaults.data(forKey: key),
              let decoded = try? JSONDecoder().decode([UserKit].self, from: data)
        else { return }
        kits = decoded
    }
}
