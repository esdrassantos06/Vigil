import SwiftUI

/// How a theme paints behind everything.
enum Backdrop: Sendable {
    case flat
    case gradient(Color, Color)
}

/// Design tokens for Vigil. See DESIGN.md.
struct Theme: Sendable {
    let bg: Color
    let surface: Color
    let surface2: Color
    let line: Color
    let inkMuted: Color
    let ink: Color
    let accent: Color
    var backdrop: Backdrop = .flat
    /// Surfaces become translucent material instead of a solid fill.
    var glass = false

    static let dark = Theme(
        bg: Color(hex: 0x0A0A0A), surface: Color(hex: 0x141414), surface2: Color(hex: 0x1F1F1F),
        line: Color(hex: 0x2E2E2E), inkMuted: Color(hex: 0xA4A4A4), ink: Color(hex: 0xF5F5F5),
        accent: Color(hex: 0xF4A437)
    )

    static let light = Theme(
        bg: Color(hex: 0xFAFAFA), surface: Color(hex: 0xF2F2F2), surface2: Color(hex: 0xE8E8E8),
        line: Color(hex: 0xD4D4D4), inkMuted: Color(hex: 0x555555), ink: Color(hex: 0x161616),
        accent: Color(hex: 0xC36D19)
    )

    /// Cool blue-grey, lifted well off black so it reads as a different room.
    static let charcoal = Theme(
        bg: Color(hex: 0x1A202B), surface: Color(hex: 0x262F3D), surface2: Color(hex: 0x313C4D),
        line: Color(hex: 0x46536A), inkMuted: Color(hex: 0xB7C2D2), ink: Color(hex: 0xF4F7FB),
        accent: Color(hex: 0xFFB347),
        backdrop: .gradient(Color(hex: 0x232C3A), Color(hex: 0x11151C))
    )

    /// Warm and dim, for a stage lit in tungsten.
    static let ember = Theme(
        bg: Color(hex: 0x201812), surface: Color(hex: 0x2E231A), surface2: Color(hex: 0x3A2C21),
        line: Color(hex: 0x574333), inkMuted: Color(hex: 0xD2BCA6), ink: Color(hex: 0xFCF6EF),
        accent: Color(hex: 0xFF9B3D),
        backdrop: .gradient(Color(hex: 0x2C2118), Color(hex: 0x140E09))
    )

    /// Deep teal with translucent surfaces.
    static let glass = Theme(
        bg: Color(hex: 0x0C1A20), surface: Color(hex: 0x16303A), surface2: Color(hex: 0x1E3F4B),
        line: Color(hex: 0x2F5F70), inkMuted: Color(hex: 0xA7C6D2), ink: Color(hex: 0xF2FAFD),
        accent: Color(hex: 0x5FD3C4),
        backdrop: .gradient(Color(hex: 0x14313B), Color(hex: 0x060F13)),
        glass: true
    )

    /// Warm cream paper, well off white so it does not read as the default.
    static let linen = Theme(
        bg: Color(hex: 0xF0E4CE), surface: Color(hex: 0xE9DABF), surface2: Color(hex: 0xDFCCAB),
        line: Color(hex: 0xC4AC84), inkMuted: Color(hex: 0x5E4C33), ink: Color(hex: 0x221A0E),
        accent: Color(hex: 0x9A4E08),
        backdrop: .gradient(Color(hex: 0xF8F0DE), Color(hex: 0xE6D6B8))
    )

    /// Cool daylight, clearly blue rather than grey.
    static let mist = Theme(
        bg: Color(hex: 0xDFE9F2), surface: Color(hex: 0xD6E2ED), surface2: Color(hex: 0xC8D7E5),
        line: Color(hex: 0xA3BAD0), inkMuted: Color(hex: 0x3F5468), ink: Color(hex: 0x0D1720),
        accent: Color(hex: 0x0A5D8F),
        backdrop: .gradient(Color(hex: 0xECF3F9), Color(hex: 0xD2DFEC))
    )

    static func of(_ scheme: ColorScheme) -> Theme {
        scheme == .dark ? .dark : .light
    }
}

/// The themes offered in Settings. `system` follows the appearance and uses the flat ones.
enum AppTheme: String, Codable, CaseIterable, Identifiable, Sendable {
    case system
    case dark, charcoal, ember, glass
    case light, linen, mist

    var id: String { rawValue }

    var name: String {
        switch self {
        case .system: "Sistema"
        case .dark: "Padrão escuro"
        case .charcoal: "Carvão"
        case .ember: "Brasa"
        case .glass: "Vidro"
        case .light: "Padrão claro"
        case .linen: "Linho"
        case .mist: "Névoa"
        }
    }

    var isDark: Bool? {
        switch self {
        case .system: nil
        case .dark, .charcoal, .ember, .glass: true
        case .light, .linen, .mist: false
        }
    }

    static var darkThemes: [AppTheme] { allCases.filter { $0.isDark == true } }
    static var lightThemes: [AppTheme] { allCases.filter { $0.isDark == false } }

    var colorScheme: ColorScheme? {
        switch isDark {
        case true: .dark
        case false: .light
        default: nil
        }
    }

    func resolve(_ scheme: ColorScheme) -> Theme {
        switch self {
        case .system: Theme.of(scheme)
        case .dark: .dark
        case .charcoal: .charcoal
        case .ember: .ember
        case .glass: .glass
        case .light: .light
        case .linen: .linen
        case .mist: .mist
        }
    }
}

/// A preview tile of one theme: its backdrop, a surface chip and its accent.
struct ThemeSwatch: View {
    let option: AppTheme
    let isSelected: Bool

    @Environment(\.colorScheme) private var scheme
    @Environment(\.theme) private var current

    var body: some View {
        let preview = option.resolve(scheme)
        return VStack(spacing: 5) {
            ZStack(alignment: .bottomLeading) {
                backdrop(preview)
                HStack(spacing: 3) {
                    RoundedRectangle(cornerRadius: 2).fill(preview.surface2).frame(width: 14, height: 8)
                    Circle().fill(preview.accent).frame(width: 7, height: 7)
                }
                .padding(5)
            }
            .frame(width: 54, height: 38)
            .clipShape(RoundedRectangle(cornerRadius: Metrics.controlRadius))
            .overlay(
                RoundedRectangle(cornerRadius: Metrics.controlRadius)
                    .stroke(isSelected ? current.accent : current.line, lineWidth: isSelected ? 2 : 1)
            )

            Text(LocalizedStringKey(option.name))
                .font(.system(size: 10))
                .foregroundStyle(isSelected ? current.ink : current.inkMuted)
                .lineLimit(1)
        }
    }

    @ViewBuilder
    private func backdrop(_ preview: Theme) -> some View {
        switch preview.backdrop {
        case .flat:
            preview.bg
        case .gradient(let top, let bottom):
            LinearGradient(colors: [top, bottom], startPoint: .top, endPoint: .bottom)
        }
    }
}

/// Reduce-transparency turns a gradient into its flat base.
struct ThemeBackdrop: View {
    @Environment(\.theme) private var theme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        Group {
            switch theme.backdrop {
            case .flat:
                theme.bg
            case .gradient(let top, let bottom):
                if reduceTransparency {
                    theme.bg
                } else {
                    LinearGradient(colors: [top, bottom], startPoint: .top, endPoint: .bottom)
                }
            }
        }
        .ignoresSafeArea()
    }
}

enum PadColor: String, CaseIterable, Codable, Sendable {
    case coral, laranja, amarelo, verde, menta, ceu, indigo, violeta, magenta

    func color(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(hex: darkHex) : Color(hex: lightHex)
    }

    private var darkHex: UInt32 {
        switch self {
        case .coral: 0xF28881
        case .laranja: 0xE99355
        case .amarelo: 0xC5A93B
        case .verde: 0x7DBF6E
        case .menta: 0x40C59B
        case .ceu: 0x2EBBE8
        case .indigo: 0x7DAAFD
        case .violeta: 0xB897F0
        case .magenta: 0xE488BE
        }
    }

    private var lightHex: UInt32 {
        switch self {
        case .coral: 0xCD605A
        case .laranja: 0xC56C21
        case .amarelo: 0xA18400
        case .verde: 0x549A44
        case .menta: 0x00A076
        case .ceu: 0x0096C5
        case .indigo: 0x5684DA
        case .violeta: 0x9470CD
        case .magenta: 0xC06099
        }
    }
}

enum Metrics {
    static let padRadius: CGFloat = 12
    static let controlRadius: CGFloat = 10
    static let padGap: CGFloat = 12
    static let zoneGap: CGFloat = 24
    static let minTarget: CGFloat = 44
}

struct ZoneLabel: View {
    let text: LocalizedStringKey
    @Environment(\.theme) private var theme

    init(_ text: LocalizedStringKey) { self.text = text }

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .textCase(.uppercase)
            .tracking(1.4)
            .foregroundStyle(theme.inkMuted)
    }
}

/// Icon button. The backing appears on hover and darkens while pressed.
struct IconButtonStyle: ButtonStyle {
    var diameter: CGFloat = 24

    func makeBody(configuration: Configuration) -> some View {
        IconButtonBody(configuration: configuration, diameter: diameter)
    }
}

private struct IconButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let diameter: CGFloat

    @Environment(\.theme) private var theme
    @State private var isHovering = false

    var body: some View {
        configuration.label
            .foregroundStyle(isHovering || configuration.isPressed ? theme.ink : theme.inkMuted)
            .frame(width: diameter, height: diameter)
            .background(background, in: Circle())
            .contentShape(Circle())
            .onHover { isHovering = $0 }
            .animation(.easeOut(duration: 0.12), value: isHovering)
    }

    private var background: Color {
        if configuration.isPressed { return theme.line }
        return isHovering ? theme.surface2 : .clear
    }
}

extension EnvironmentValues {
    @Entry var theme: Theme = .dark
}

extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}
