import SwiftUI

/// Filled blue call-to-action. Matches the reference "primary" button.
struct WVPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(
                (configuration.isPressed ? Theme.accentHover : Theme.accent)
                    .opacity(isEnabled ? 1 : 0.4),
                in: RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
            )
            .contentShape(Rectangle())
            .opacity(isEnabled ? 1 : 0.7)
    }
}

/// Dark bordered "chip" button, e.g. the `Change` control next to a keycap.
struct WVSecondaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    var role: ButtonRole?

    private var foreground: Color {
        role == .destructive ? Theme.danger : Theme.textPrimary
    }

    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous)
        return configuration.label
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(foreground)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                (configuration.isPressed ? Theme.surfaceElevated : Theme.inset),
                in: shape
            )
            .overlay(shape.strokeBorder(Theme.border, lineWidth: 1))
            .contentShape(Rectangle())
            .opacity(isEnabled ? 1 : 0.4)
    }
}

/// Text-only ghost button, e.g. `Clear` / `Refresh`.
struct WVGhostButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    var role: ButtonRole?

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(role == .destructive ? Theme.danger : Theme.textSecondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
            .opacity(configuration.isPressed ? 0.6 : (isEnabled ? 1 : 0.4))
    }
}

extension ButtonStyle where Self == WVPrimaryButtonStyle {
    static var wvPrimary: WVPrimaryButtonStyle { WVPrimaryButtonStyle() }
}

extension ButtonStyle where Self == WVSecondaryButtonStyle {
    static var wvSecondary: WVSecondaryButtonStyle { WVSecondaryButtonStyle() }
    static func wvSecondary(role: ButtonRole?) -> WVSecondaryButtonStyle {
        WVSecondaryButtonStyle(role: role)
    }
}

extension ButtonStyle where Self == WVGhostButtonStyle {
    static var wvGhost: WVGhostButtonStyle { WVGhostButtonStyle() }
    static func wvGhost(role: ButtonRole?) -> WVGhostButtonStyle {
        WVGhostButtonStyle(role: role)
    }
}
