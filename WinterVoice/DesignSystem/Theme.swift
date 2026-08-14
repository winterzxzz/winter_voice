import SwiftUI

/// Central design tokens for WinterVoice.
///
/// The palette, spacing, and typography here reproduce the dark, card-based
/// look of a modern menu-bar dictation app: a near-black canvas, softly
/// elevated surfaces separated by hairline borders, a blue action accent, and
/// a green "live" accent for active/recording states. Every surface paints an
/// explicit color — nothing relies on the system window material — so the UI
/// reads identically regardless of the host appearance.
enum Theme {

    // MARK: Canvas & surfaces

    /// Window background — the darkest layer everything else sits on.
    static let canvas = Color(hex: 0x0A0A0B)
    /// Sidebar background, a hair warmer than the canvas so the split reads.
    static let sidebar = Color(hex: 0x0E0E10)
    /// Default card surface.
    static let surface = Color(white: 1.0, opacity: 0.035)
    /// A card nested inside another card, or a pressed/elevated surface.
    static let surfaceElevated = Color(white: 1.0, opacity: 0.06)
    /// Small inset squares that hold row icons and keycaps.
    static let inset = Color(white: 1.0, opacity: 0.05)

    // MARK: Borders

    static let border = Color(white: 1.0, opacity: 0.08)
    static let borderStrong = Color(white: 1.0, opacity: 0.13)
    static let separator = Color(white: 1.0, opacity: 0.06)

    // MARK: Text

    static let textPrimary = Color(hex: 0xF2F2F3)
    static let textSecondary = Color(hex: 0x8B8B90)
    static let textTertiary = Color(hex: 0x5B5B60)

    // MARK: Accents

    /// Primary action blue.
    static let accent = Color(hex: 0x3B82F6)
    static let accentHover = Color(hex: 0x2563EB)
    /// Live / active / success green.
    static let success = Color(hex: 0x4ADE80)
    static let successSurface = Color(red: 0.13, green: 0.77, blue: 0.37, opacity: 0.14)
    static let successBorder = Color(red: 0.13, green: 0.77, blue: 0.37, opacity: 0.28)
    /// Destructive red.
    static let danger = Color(hex: 0xF55459)
    /// Warning amber for degraded states.
    static let warning = Color(hex: 0xF5A623)

    /// Selected sidebar-row fill.
    static let selectionFill = Color(white: 1.0, opacity: 0.09)

    // MARK: Metrics

    enum Radius {
        static let card: CGFloat = 16
        static let row: CGFloat = 12
        static let control: CGFloat = 10
        static let chip: CGFloat = 8
        static let icon: CGFloat = 9
    }

    enum Space {
        static let xs: CGFloat = 6
        static let sm: CGFloat = 10
        static let md: CGFloat = 16
        static let lg: CGFloat = 24
        static let xl: CGFloat = 32
    }
}

extension Color {
    /// Build a color from a 0xRRGGBB literal.
    init(hex: UInt32, opacity: Double = 1.0) {
        let r = Double((hex >> 16) & 0xFF) / 255.0
        let g = Double((hex >> 8) & 0xFF) / 255.0
        let b = Double(hex & 0xFF) / 255.0
        self.init(.sRGB, red: r, green: g, blue: b, opacity: opacity)
    }
}

extension Font {
    /// Page/section title — semibold with the tight tracking of the reference UI.
    static let wvTitle = Font.system(size: 18, weight: .semibold)
    static let wvHeadline = Font.system(size: 15, weight: .semibold)
    static let wvBody = Font.system(size: 13, weight: .regular)
    static let wvRowTitle = Font.system(size: 14, weight: .medium)
    static let wvCaption = Font.system(size: 12, weight: .regular)
    static let wvKeycap = Font.system(size: 12, weight: .medium, design: .rounded)
}
