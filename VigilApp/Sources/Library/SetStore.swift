import Foundation
import Observation

/// Playing context: tonal pad sound, filters, metronome and which kit is active.
/// The eight pads are not here; the kit owns them.
struct VigilSet: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    var name: String
    var padSoundID: String
    var kit: KitRef?
    var settings: Settings
}

@MainActor
@Observable
final class SetStore {
    private(set) var sets: [VigilSet] = []

    @ObservationIgnored private let key = "userSets"
    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        restore()
    }

    @discardableResult
    func save(_ set: VigilSet) -> VigilSet {
        sets.append(set)
        persist()
        return set
    }

    func update(_ set: VigilSet) {
        guard let index = sets.firstIndex(where: { $0.id == set.id }), sets[index] != set else { return }
        sets[index] = set
        persist()
    }

    func rename(_ set: VigilSet, to name: String) {
        guard let index = sets.firstIndex(where: { $0.id == set.id }) else { return }
        sets[index].name = name
        persist()
    }

    func delete(_ set: VigilSet) {
        sets.removeAll { $0.id == set.id }
        persist()
    }

    private func persist() {
        defaults.store(sets, forKey: key)
    }

    private func restore() {
        guard let decoded = defaults.decoded([VigilSet].self, forKey: key) else { return }
        sets = decoded
    }
}
