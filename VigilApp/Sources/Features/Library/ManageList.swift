import SwiftUI

struct ManageItem: Identifiable, Equatable {
    let id: UUID
    let name: String
    let detail: String?
}

struct ManageList: View {
    let title: String
    let items: [ManageItem]
    let emptyTitle: String
    let emptyMessage: String
    let onRename: (ManageItem, String) -> Void
    let onDelete: (ManageItem) -> Void
    let onSelect: ((ManageItem) -> Void)?
    let onClose: () -> Void

    @Environment(\.theme) private var theme
    @State private var selection: UUID?
    @State private var renaming: ManageItem?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SheetHeader(title: LocalizedStringKey(title), onClose: onClose)
                .padding(.horizontal, Metrics.zoneGap)
                .padding(.top, 20)
                .padding(.bottom, 16)

            Rectangle()
                .fill(theme.line)
                .frame(height: 1)

            if items.isEmpty {
                empty
            } else {
                ScrollView {
                    VStack(spacing: 6) {
                        ForEach(items) { item in
                            row(item)
                        }
                    }
                    .padding(Metrics.zoneGap)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(width: 480, height: 560)
        .background(theme.bg)
        .sheet(item: $renaming) { item in
            NamePrompt(
                title: "Renomear",
                placeholder: item.name,
                initial: item.name,
                onCancel: { renaming = nil },
                onConfirm: { newName in
                    onRename(item, newName)
                    renaming = nil
                }
            )
            .environment(\.theme, theme)
        }
    }

    private func row(_ item: ManageItem) -> some View {
        let isSelected = selection == item.id
        return HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(item.name)
                    .font(.system(size: 17, weight: .regular, design: .serif))
                    .foregroundStyle(theme.ink)
                if let detail = item.detail {
                    Text(detail)
                        .font(.system(size: 11))
                        .foregroundStyle(theme.inkMuted)
                }
            }
            Spacer()
            if isSelected {
                Button("Nomear") { renaming = item }
                Button("Apagar", role: .destructive) { onDelete(item) }
            }
        }
        .buttonStyle(.bordered)
        .font(.system(size: 12))
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(minHeight: Metrics.minTarget)
        .background(
            isSelected ? theme.surface2 : theme.surface,
            in: RoundedRectangle(cornerRadius: Metrics.controlRadius)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            selection = item.id
            onSelect?(item)
        }
    }

    private var empty: some View {
        VStack(spacing: 10) {
            FlameMark()
                .fill(theme.line)
                .frame(width: 22, height: 48)
            Text(emptyTitle)
                .font(.system(size: 20, weight: .regular, design: .serif))
                .foregroundStyle(theme.ink)
            Text(emptyMessage)
                .font(.system(size: 13))
                .foregroundStyle(theme.inkMuted)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 300)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(Metrics.zoneGap)
    }
}

#Preview("Gerenciar — vazio") {
    ManageList(
        title: "Gerenciar Sets",
        items: [],
        emptyTitle: "Nenhum set salvo",
        emptyMessage: "Um set guarda o som do pad, o kit e os volumes. Salve o atual para voltar a ele depois.",
        onRename: { _, _ in },
        onDelete: { _ in },
        onSelect: nil,
        onClose: {}
    )
    .environment(\.theme, .dark)
}
