import Foundation
import Observation

extension AppModel {

    func assign(_ pad: DrumPad, sample: Sample) {
        do {
            try drums.load(
                url: library.url(for: sample),
                into: pad,
                name: sample.displayName,
                source: .custom(sample.id)
            )
            savePads()
            toasts.success(t("\(sample.displayName) no pad \(pad.label)."))
        } catch {
            toasts.error(message(for: error))
        }
    }

    func assign(_ pad: DrumPad, kit: FactoryKit, slotIndex: Int) {
        guard let slot = kit.slots[safe: slotIndex],
              let url = catalog.url(for: slot.file) else {
            toasts.error(t("Som de fábrica não encontrado."))
            return
        }
        do {
            try drums.load(
                url: url,
                into: pad,
                name: slot.name,
                source: .native(kit: kit.id, slot: slotIndex)
            )
            savePads()
            toasts.success(t("\(slot.name) no pad \(pad.label)."))
        } catch {
            toasts.error(message(for: error))
        }
    }

    func setColor(_ pad: DrumPad, to color: PadColor) {
        pad.color = color
        savePads()
    }

    func clear(_ pad: DrumPad) {
        drums.clear(pad)
        savePads()
        toasts.info(t("Pad \(pad.label) limpo."))
    }

    func handleImport(_ result: Result<[URL], Error>) {
        switch result {
        case .failure(let error):
            toasts.error(message(for: error))
        case .success(let urls):
            guard let url = urls.first else { return }
            do {
                let sample = try library.importFile(from: url)
                toasts.success(t("\(sample.displayName) importado."))
            } catch {
                toasts.error(message(for: error))
            }
        }
    }

    func delete(_ sample: Sample) {
        do {
            try library.delete(sample)
        } catch {
            toasts.error(message(for: error))
            return
        }
        for pad in drums.pads where pad.source == .custom(sample.id) {
            drums.clear(pad)
        }
        savePads()
        toasts.info(t("\(sample.displayName) removido."))
    }

}
