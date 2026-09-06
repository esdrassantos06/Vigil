import SwiftUI

struct MainMenu: View {
    let padSounds: [PadSoundInfo]
    let activeSoundID: String
    let kits: [FactoryKit]
    let userKits: [UserKit]
    let currentKit: KitRef?
    let onSelectSound: (PadSoundInfo) -> Void
    let onSelectKit: (FactoryKit) -> Void
    let onSelectUserKit: (UserKit) -> Void
    let onSaveKit: () -> Void
    let onDeleteUserKit: (UserKit) -> Void
    let onImport: () -> Void
    let currentSetName: String?
    let sets: [VigilSet]
    let onSelectSet: (VigilSet) -> Void
    let onDefaultSet: () -> Void
    let onSaveSet: () -> Void
    let onManageSets: () -> Void
    let onManageSamples: () -> Void

    @Environment(\.theme) private var theme

    var body: some View {
        Menu {
            Menu("Sons de Pads") {
                ForEach(padSounds) { sound in
                    Button {
                        onSelectSound(sound)
                    } label: {
                        Label(
                            LocalizedStringKey(sound.name),
                            systemImage: sound.id == activeSoundID ? "checkmark" : sound.icon
                        )
                    }
                }
            }

            Menu("Drum Kits") {
                ForEach(kits) { kit in
                    Button {
                        onSelectKit(kit)
                    } label: {
                        Label(
                            kit.name,
                            systemImage: currentKit == .factory(kit.id) ? "checkmark" : "square.grid.2x2"
                        )
                    }
                }

                if !userKits.isEmpty {
                    Divider()
                    ForEach(userKits) { kit in
                        Button {
                            onSelectUserKit(kit)
                        } label: {
                            Label(
                                kit.name,
                                systemImage: currentKit == .user(kit.id) ? "checkmark" : "person"
                            )
                        }
                    }
                }
            }

            Button("Salvar kit atual…", action: onSaveKit)

            if !userKits.isEmpty {
                Menu("Apagar kit") {
                    ForEach(userKits) { kit in
                        Button(kit.name, role: .destructive) { onDeleteUserKit(kit) }
                    }
                }
            }

            Divider()

            Menu("Sample Drum") {
                Button("Importar Sample…", action: onImport)
                Button("Gerenciar Samples…", action: onManageSamples)
            }

            Divider()

            Button("Salvar novo Set…", action: onSaveSet)

            // Menu(String) does not localize; it needs a LocalizedStringKey or a label.
            Menu {
                Button("Padrão", action: onDefaultSet)
                if !sets.isEmpty {
                    Divider()
                    ForEach(sets) { set in
                        Button(set.name) { onSelectSet(set) }
                    }
                }
            } label: {
                if let name = currentSetName { Text(name) } else { Text("Padrão") }
            }

            Button("Gerenciar Sets…", action: onManageSets)
        } label: {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(theme.ink)
                .frame(width: Metrics.minTarget, height: Metrics.minTarget)
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityLabel("Menu")
    }
}
