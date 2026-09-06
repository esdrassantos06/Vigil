import SwiftUI

/// Design tokens for Vigil. See DESIGN.md.
struct Theme: Sendable {
    let bg: Color
    let surface: Color
    let surface2: Color
    let line: Color
    let inkMuted: Color
    let ink: Color
    let accent: Color

    static let dark = Theme(
        bg: Color(hex: 0x0A0A0A),
        surface: Color(hex: 0x141414),
        surface2: Color(hex: 0x1F1F1F),
        line: Color(hex: 0x2E2E2E),
        inkMuted: Color(hex: 0xA4A4A4),
        ink: Color(hex: 0xF5F5F5),
        accent: Color(hex: 0xF4A437)
    )

    static let light = Theme(
        bg: Color(hex: 0xFAFAFA),
        surface: Color(hex: 0xF2F2F2),
        surface2: Color(hex: 0xE8E8E8),
        line: Color(hex: 0xD4D4D4),
        inkMuted: Color(hex: 0x555555),
        ink: Color(hex: 0x161616),
        accent: Color(hex: 0xC36D19)
    )

    static func of(_ scheme: ColorScheme) -> Theme {
        scheme == .dark ? .dark : .light
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
