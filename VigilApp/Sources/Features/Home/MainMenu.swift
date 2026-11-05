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
            Section("Som") {
                Menu {
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
                } label: {
                    Label("Sons de Pads", systemImage: "waveform")
                }

                Menu {
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
                } label: {
                    Label("Drum Kits", systemImage: "square.grid.2x2")
                }
            }

            Section("Kit") {
                Button(action: onSaveKit) {
                    Label("Salvar kit atual…", systemImage: "square.and.arrow.down")
                }
                if !userKits.isEmpty {
                    Menu {
                        ForEach(userKits) { kit in
                            Button(kit.name, role: .destructive) { onDeleteUserKit(kit) }
                        }
                    } label: {
                        Label("Apagar kit", systemImage: "trash")
                    }
                }
            }

            Section("Samples") {
                Button(action: onImport) {
                    Label("Importar Sample…", systemImage: "square.and.arrow.down.on.square")
                }
                Button(action: onManageSamples) {
                    Label("Gerenciar Samples…", systemImage: "folder")
                }
            }

            Section("Set") {
                Menu {
                    Button {
                        onDefaultSet()
                    } label: {
                        Label("Padrão", systemImage: currentSetName == nil ? "checkmark" : "music.note.list")
                    }
                    if !sets.isEmpty {
                        Divider()
                        ForEach(sets) { set in
                            Button {
                                onSelectSet(set)
                            } label: {
                                Label(set.name, systemImage: set.name == currentSetName ? "checkmark" : "music.note.list")
                            }
                        }
                    }
                } label: {
                    if let name = currentSetName {
                        Label(name, systemImage: "music.note.list")
                    } else {
                        Label("Padrão", systemImage: "music.note.list")
                    }
                }
                Button(action: onSaveSet) {
                    Label("Salvar novo Set…", systemImage: "plus.rectangle.on.rectangle")
                }
                Button(action: onManageSets) {
                    Label("Gerenciar Sets…", systemImage: "slider.horizontal.3")
                }
            }
        } label: {
            Image(systemName: "line.3.horizontal")
        }
        .menuStyle(.button)
        .glassButton(shape: .circle)
        .controlSize(.large)
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityLabel("Menu")
    }
}
