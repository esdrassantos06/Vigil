import SwiftUI

/// A pane of Liquid Glass on macOS 26 / iPadOS 26, system material below that, and an opaque
/// themed surface whenever Reduce Transparency is on.
private struct GlassPane<S: InsettableShape>: ViewModifier {
    let shape: S
    let tint: Color?

    @Environment(\.theme) private var theme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.isInsideGlass) private var isInsideGlass

    func body(content: Content) -> some View {
        pane(content).environment(\.isInsideGlass, true)
    }

    /// Glass on glass renders muddy, so a pane inside another becomes a quiet fill. Top-level
    /// glass carries a wash of the theme ground so it stays dark over a black stage.
    @ViewBuilder
    private func pane(_ content: Content) -> some View {
        if isInsideGlass {
            content.background((tint ?? theme.ink.opacity(0.08)), in: shape)
        } else if reduceTransparency {
            content
                .background(theme.surface, in: shape)
                .overlay(shape.strokeBorder(theme.line, lineWidth: 1))
        } else if #available(macOS 26, iOS 26, *) {
            content
                .background(theme.bg.opacity(0.3), in: shape)
                .glassEffect(glass, in: shape)
                .overlay(shape.strokeBorder(theme.ink.opacity(0.1), lineWidth: 1))
        } else {
            content
                .background(.ultraThinMaterial, in: shape)
                .background((tint ?? theme.surface).opacity(0.35), in: shape)
                .overlay(shape.strokeBorder(theme.line.opacity(0.8), lineWidth: 1))
        }
    }

    /// Not `.interactive()`: it keeps the main thread busy tracking the pointer even when
    /// idle, which roughly tripled idle CPU here.
    @available(macOS 26, iOS 26, *)
    private var glass: Glass { Glass.regular.tint(tint) }
}

extension EnvironmentValues {
    /// True below a glass pane, so nested panes do not stack glass.
    @Entry var isInsideGlass = false
}

extension View {
    /// Puts the view on a glass pane of the given shape.
    /// - Parameters:
    ///   - shape: the pane's outline.
    ///   - tint: colour carried in the glass, for a pane whose colour means something.
    func glassPane<S: InsettableShape>(_ shape: S, tint: Color? = nil) -> some View {
        modifier(GlassPane(shape: shape, tint: tint))
    }

    /// A rounded glass pane with the continuous corners the platform uses.
    func glassPane(radius: CGFloat, tint: Color? = nil) -> some View {
        glassPane(RoundedRectangle(cornerRadius: radius, style: .continuous), tint: tint)
    }
}

extension View {
    /// The platform's own Liquid Glass button on macOS 26 / iPadOS 26, a bordered button below.
    /// - Parameters:
    ///   - isOn: a toggle that is on takes the prominent, tinted glass.
    ///   - tint: the colour of the prominent glass.
    ///   - shape: capsule for labels, circle for a lone symbol.
    @ViewBuilder
    func glassButton(isOn: Bool = false, tint: Color? = nil,
                     shape: ButtonBorderShape = .capsule) -> some View {
        let shaped = buttonBorderShape(shape)
        if #available(macOS 26, iOS 26, *) {
            if isOn {
                shaped.buttonStyle(.glassProminent).tint(tint)
            } else {
                shaped.buttonStyle(.glass)
            }
        } else if isOn {
            shaped.buttonStyle(.borderedProminent).tint(tint)
        } else {
            shaped.buttonStyle(.bordered)
        }
    }
}

extension Theme {
    /// The flame's colours from its base to its white core: the sounding note and nothing else.
    var flame: [Color] { [accent.opacity(0), accent, Color(hex: 0xFFF6E0)] }

    /// An idle indicator: present enough to count, quiet enough not to read as on.
    var idle: Color { inkMuted.opacity(0.35) }
}
