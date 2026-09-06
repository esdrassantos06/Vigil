import Foundation
import Observation

extension AppModel {
    func saveCurrentSet(named name: String) {
        let set = VigilSet(
            id: UUID(),
            name: name,
            padSoundID: tonal.soundID,
            kit: currentKit,
            settings: settings
        )
        sets.save(set)
        currentSetID = set.id
        toasts.success(t("Set \(set.name) salvo."))
    }

    func loadSet(_ set: VigilSet) {
        isLoading = true
        settings = set.settings.clamped()
        tonal.selectSound(set.padSoundID)
        currentSetID = set.id
        if let kit = set.kit {
            apply(kit)
        }
        isLoading = false
        savePads()
        toasts.success(t("Set \(set.name) carregado."))
    }

    /// A clean state that is never written, so editing it dirties nothing.
    func loadDefaultSet() {
        isLoading = true
        currentSetID = nil
        settings = Settings()
        tonal.selectSound(catalog.padSoundList.first?.id ?? "Default")
        loadDefaultKit()
        isLoading = false
        toasts.info(t("Set padrão carregado."))
    }

    func renameSet(_ set: VigilSet, to name: String) {
        sets.rename(set, to: name)
        toasts.info(t("Set renomeado para \(name)."))
    }

    func deleteSet(_ set: VigilSet) {
        sets.delete(set)
        if currentSetID == set.id { currentSetID = nil }
        toasts.info(t("Set \(set.name) apagado."))
    }

    func renameSample(_ sample: Sample, to name: String) {
        library.rename(sample, to: name)
        for pad in drums.pads where pad.source == .custom(sample.id) {
            pad.name = name
        }
        toasts.info(t("Sample renomeado para \(name)."))
    }

    func saveCurrentKit(named name: String) {
        let kit = userKits.save(name: name, slots: currentSlots())
        currentKit = .user(kit.id)
        savePads()
        toasts.success(t("Kit \(kit.name) salvo."))
    }

    func selectUserKit(_ kit: UserKit) {
        var unreadable = 0
        for (index, pad) in drums.pads.enumerated() {
            guard let slot = kit.slots[safe: index] else { continue }
            pad.color = slot.color
            pad.volume = slot.volume
            if !apply(source: slot.source, to: pad) { unreadable += 1 }
        }
        currentKit = .user(kit.id)
        savePads()
        toasts.success(t("Kit \(kit.name) carregado."))
        reportUnreadable(unreadable)
    }

    func deleteUserKit(_ kit: UserKit) {
        userKits.delete(kit)
        if currentKit == .user(kit.id) { currentKit = nil }
        savePads()
        toasts.info(t("Kit \(kit.name) apagado."))
    }

    var allKits: [KitRef] {
        catalog.kits.map { KitRef.factory($0.id) } + userKits.kits.map { KitRef.user($0.id) }
    }

    func apply(_ ref: KitRef) {
        switch ref {
        case .factory(let id):
            guard let kit = catalog.kit(id: id) else {
                toasts.error(t("Kit não encontrado."))
                return
            }
            selectKit(kit)
        case .user(let id):
            guard let kit = userKits.kit(id: id) else {
                toasts.error(t("Kit não encontrado."))
                return
            }
            selectUserKit(kit)
        }
    }

    @discardableResult
    func apply(source: PadSource, to pad: DrumPad) -> Bool {
        switch source {
        case .empty:
            drums.clear(pad)
            return true
        case .custom(let sampleID):
            guard let sample = library.samples.first(where: { $0.id == sampleID }) else {
                drums.clear(pad); return false
            }
            return load(library.url(for: sample), into: pad,
                        name: sample.displayName, source: source)
        case .native(let kitID, let slotIndex):
            guard let kit = catalog.kit(id: kitID),
                  let slot = kit.slots[safe: slotIndex],
                  let url = catalog.url(for: slot.file) else { drums.clear(pad); return false }
            return load(url, into: pad, name: slot.name, source: source)
        }
    }

}
