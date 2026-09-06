import Foundation
import SwiftUI
import Testing
@testable import Vigil

/// A theme that looks good and cannot be read on a dark stage is a broken theme, so contrast
/// is a requirement here rather than an intention.
@MainActor
@Suite("Themes")
struct ThemeTests {

    /// Relative luminance per WCAG 2.2.
    private func luminance(_ color: Color) -> Double {
        let components = NSColor(color).usingColorSpace(.sRGB) ?? .black
        func channel(_ value: CGFloat) -> Double {
            let v = Double(value)
            return v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(components.redComponent)
            + 0.7152 * channel(components.greenComponent)
            + 0.0722 * channel(components.blueComponent)
    }

    private func contrast(_ a: Color, _ b: Color) -> Double {
        let first = luminance(a), second = luminance(b)
        let lighter = max(first, second), darker = min(first, second)
        return (lighter + 0.05) / (darker + 0.05)
    }

    private var themes: [(AppTheme, Theme)] {
        AppTheme.allCases.filter { $0 != .system }.map { ($0, $0.resolve(.dark)) }
    }

    @Test("Body text clears 4.5:1 on every theme")
    func bodyContrast() {
        for (id, theme) in themes {
            let ratio = contrast(theme.ink, theme.bg)
            #expect(ratio >= 4.5, "\(id.rawValue): ink on bg is \(ratio)")
        }
    }

    @Test("Muted text clears 4.5:1 on every theme")
    func mutedContrast() {
        for (id, theme) in themes {
            let ratio = contrast(theme.inkMuted, theme.bg)
            #expect(ratio >= 4.5, "\(id.rawValue): muted on bg is \(ratio)")
        }
    }

    @Test("Ink stays readable on the panel fills, not just the backdrop")
    func surfaceContrast() {
        for (id, theme) in themes {
            #expect(contrast(theme.ink, theme.surface) >= 4.5, "\(id.rawValue): ink on surface")
            #expect(contrast(theme.ink, theme.surface2) >= 4.5, "\(id.rawValue): ink on surface2")
        }
    }

    @Test("Every pad colour stays visible against its theme")
    func padColoursStayVisible() {
        for (id, theme) in themes {
            let scheme: ColorScheme = id.isDark == true ? .dark : .light
            for pad in PadColor.allCases {
                let ratio = contrast(pad.color(scheme), theme.bg)
                #expect(ratio >= 2.0, "\(id.rawValue) \(pad.rawValue): \(ratio)")
            }
        }
    }

    @Test("The default theme stays flat, so a clean install opens plain")
    func defaultThemeIsFlat() {
        if case .flat = AppTheme.dark.resolve(.dark).backdrop {} else {
            Issue.record("the default dark theme is not flat")
        }
        if case .flat = AppTheme.light.resolve(.light).backdrop {} else {
            Issue.record("the default light theme is not flat")
        }
        #expect(!AppTheme.dark.resolve(.dark).glass)
    }

    @Test("System follows the appearance")
    func systemFollowsAppearance() {
        #expect(AppTheme.system.colorScheme == nil)
        #expect(AppTheme.system.resolve(.dark).bg == Theme.dark.bg)
        #expect(AppTheme.system.resolve(.light).bg == Theme.light.bg)
    }

    @Test("Every theme lands in exactly one list")
    func themesAreGrouped() {
        let grouped = AppTheme.darkThemes.count + AppTheme.lightThemes.count
        #expect(grouped == AppTheme.allCases.count - 1, "system must not be in either list")
        #expect(AppTheme.darkThemes.allSatisfy { $0.isDark == true })
        #expect(AppTheme.lightThemes.allSatisfy { $0.isDark == false })
    }
}
