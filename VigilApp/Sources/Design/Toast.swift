import SwiftUI
import Observation

struct Toast: Identifiable, Equatable {
    enum Kind { case info, success, error }
    let id = UUID()
    let kind: Kind
    let message: String

    var duration: Duration { kind == .error ? .seconds(6) : .seconds(3.5) }
}

/// One toast at a time, top right. No queue: a new toast replaces the current one, and
/// only an error replaces an error.
@MainActor
@Observable
final class ToastCenter {
    private(set) var current: Toast?
    @ObservationIgnored private var task: Task<Void, Never>?

    func info(_ message: String) { show(Toast(kind: .info, message: message)) }
    func success(_ message: String) { show(Toast(kind: .success, message: message)) }
    func error(_ message: String) { show(Toast(kind: .error, message: message)) }

    func dismiss() {
        task?.cancel()
        task = nil
        current = nil
    }

    private func show(_ toast: Toast) {
        if current?.kind == .error, toast.kind != .error { return }
        present(toast)
    }

    private func present(_ toast: Toast) {
        task?.cancel()
        current = toast
        task = Task { [weak self] in
            try? await Task.sleep(for: toast.duration)
            guard !Task.isCancelled else { return }
            self?.current = nil
            self?.task = nil
        }
    }
}

extension View {
    /// A macOS sheet is a separate window, so whatever is on top needs its own layer.
    @MainActor
    func toasts(_ center: ToastCenter) -> some View {
        overlay { ToastLayer(center: center) }
    }
}

@MainActor
struct ToastLayer: View {
    let center: ToastCenter
    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack {
            if let toast = center.current {
                row(toast)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .padding(Metrics.zoneGap)
        .animation(.easeOut(duration: 0.22), value: center.current)
        .allowsHitTesting(center.current != nil)
    }

    private func row(_ toast: Toast) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon(toast.kind))
                .foregroundStyle(tint(toast.kind))
            Text(toast.message)
                .font(.system(size: 15))
                .foregroundStyle(theme.ink)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button { center.dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
            }
            .buttonStyle(IconButtonStyle())
            .help("Fechar")
            .accessibilityLabel("Fechar")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .frame(maxWidth: 380, alignment: .leading)
        .background(theme.surface, in: RoundedRectangle(cornerRadius: Metrics.padRadius))
        .overlay(
            RoundedRectangle(cornerRadius: Metrics.padRadius)
                .stroke(theme.line, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.28), radius: 8, y: 2)
    }

    private func icon(_ kind: Toast.Kind) -> String {
        switch kind {
        case .info: "info.circle"
        case .success: "checkmark.circle"
        case .error: "exclamationmark.triangle"
        }
    }

    private func tint(_ kind: Toast.Kind) -> Color {
        switch kind {
        case .info: theme.inkMuted
        case .success: theme.accent
        case .error: PadColor.coral.color(scheme)
        }
    }
}

#Preview("Toasts") {
    let center = ToastCenter()
    return ToastLayer(center: center)
        .environment(\.theme, .dark)
        .frame(width: 520, height: 160)
        .background(Theme.dark.bg)
        .task { center.error("Não foi possível ler o arquivo. Se estiver no iCloud, baixe antes.") }
}
