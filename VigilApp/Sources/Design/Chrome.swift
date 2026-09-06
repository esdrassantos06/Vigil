import SwiftUI

/// The flame from `assets/logo-mark.svg`, as a shape so it takes the theme colour.
struct FlameMark: Shape {
    private static let box = CGRect(x: 400, y: 250, width: 224, height: 492)

    func path(in rect: CGRect) -> Path {
        let scale = min(rect.width / Self.box.width, rect.height / Self.box.height)
        let offsetX = rect.midX - Self.box.midX * scale
        let offsetY = rect.midY - Self.box.midY * scale
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: x * scale + offsetX, y: y * scale + offsetY)
        }

        var path = Path()
        path.move(to: point(512, 250))
        path.addCurve(to: point(400, 512), control1: point(430, 360), control2: point(400, 430))
        path.addCurve(to: point(512, 742), control1: point(400, 612), control2: point(460, 690))
        path.addCurve(to: point(624, 512), control1: point(564, 690), control2: point(624, 612))
        path.addCurve(to: point(512, 250), control1: point(624, 430), control2: point(594, 360))
        path.closeSubpath()
        return path
    }
}

struct Wordmark: View {
    var size: CGFloat = 24

    @Environment(\.theme) private var theme

    var body: some View {
        HStack(spacing: 8) {
            FlameMark()
                .fill(theme.accent)
                .frame(width: size * 0.42, height: size * 0.92)
            Text("Vigil")
                .font(.system(size: size, weight: .regular, design: .serif))
                .foregroundStyle(theme.ink)
        }
        .accessibilityElement()
        .accessibilityLabel("Vigil")
    }
}

/// Shared sheet header.
struct SheetHeader: View {
    let title: LocalizedStringKey
    let onClose: () -> Void

    @Environment(\.theme) private var theme

    var body: some View {
        HStack(spacing: 10) {
            FlameMark()
                .fill(theme.accent)
                .frame(width: 9, height: 20)
            Text(title)
                .font(.system(size: 26, weight: .regular, design: .serif))
                .foregroundStyle(theme.ink)
            Spacer(minLength: 0)
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .semibold))
            }
            .buttonStyle(IconButtonStyle(diameter: 28))
            .help("Fechar")
            .accessibilityLabel("Fechar")
        }
    }
}

/// Sheet whose header stays put while the body scrolls.
struct Sheet<Content: View, Footer: View>: View {
    let title: LocalizedStringKey
    let onClose: () -> Void
    @ViewBuilder let content: () -> Content
    @ViewBuilder let footer: () -> Footer

    @Environment(\.theme) private var theme

    init(
        _ title: LocalizedStringKey,
        onClose: @escaping () -> Void,
        @ViewBuilder content: @escaping () -> Content,
        @ViewBuilder footer: @escaping () -> Footer = { EmptyView() }
    ) {
        self.title = title
        self.onClose = onClose
        self.content = content
        self.footer = footer
    }

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(title: title, onClose: onClose)
                .padding(.horizontal, Metrics.zoneGap)
                .padding(.top, 20)
                .padding(.bottom, 16)

            Rectangle()
                .fill(theme.line)
                .frame(height: 1)

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    content()
                }
                .padding(Metrics.zoneGap)
            }

            footer()
        }
        .background(ThemeBackdrop())
    }
}

struct Panel<Content: View>: View {
    let title: LocalizedStringKey
    @ViewBuilder let content: () -> Content

    @Environment(\.theme) private var theme

    init(_ title: LocalizedStringKey, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ZoneLabel(title)
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.surface, in: RoundedRectangle(cornerRadius: Metrics.padRadius))
        .overlay(
            RoundedRectangle(cornerRadius: Metrics.padRadius)
                .stroke(theme.line, lineWidth: 1)
        )
    }
}

#Preview("Marca") {
    VStack(alignment: .leading, spacing: 24) {
        Wordmark(size: 34)
        SheetHeader(title: "Configurações", onClose: {})
        Panel("Metrônomo") {
            Text(verbatim: "content").foregroundStyle(Theme.dark.inkMuted)
        }
    }
    .padding(24)
    .frame(width: 420)
    .background(Theme.dark.bg)
    .environment(\.theme, .dark)
}
