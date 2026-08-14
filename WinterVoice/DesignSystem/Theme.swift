import SwiftUI

/// Central design tokens for WinterVoice.
///
/// Palette and type reproduce the BridgeVoice reference: a pure-black rail
/// (titlebar + sidebar) beside a near-black content canvas, dark-gray cards
/// with hairline borders, a white "selected" language (nav pill, toggles,
/// primary buttons), and Inter as the app-wide typeface. Every surface paints
/// an explicit color — nothing relies on the system window material — so the
/// UI reads identically regardless of the host appearance.
enum Theme {

    // MARK: Canvas & surfaces

    /// Content-area background.
    static let canvas = Color(hex: 0x0A0A0A)
    /// Sidebar and titlebar rail — pure black so it fuses with the window chrome.
    static let sidebar = Color(hex: 0x030303)
    /// Default card surface.
    static let surface = Color(hex: 0x151517)
    /// A card nested inside another card, or a pressed/elevated surface.
    static let surfaceElevated = Color(hex: 0x1E1E21)
    /// Small inset squares that hold row icons, keycaps, and inputs.
    static let inset = Color(hex: 0x1A1A1D)

    // MARK: Borders

    static let border = Color(white: 1.0, opacity: 0.06)
    static let borderStrong = Color(white: 1.0, opacity: 0.13)
    static let separator = Color(white: 1.0, opacity: 0.06)

    // MARK: Text

    static let textPrimary = Color(hex: 0xF7F7F8)
    static let textSecondary = Color(hex: 0x9C9CA3)
    static let textTertiary = Color(hex: 0x69696F)
    /// Text placed on a white fill (nav pill, primary button).
    static let textOnWhite = Color(hex: 0x111113)

    // MARK: Accents

    /// Primary action blue (brand mark).
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

    /// Hovered sidebar-row fill; the selected row is a solid white pill.
    static let hoverFill = Color(white: 1.0, opacity: 0.06)
    /// Selected chip fill — elevated dark with a brighter border, per reference.
    static let chipSelected = Color(hex: 0x232326)
    static let chipSelectedBorder = Color(white: 1.0, opacity: 0.22)

    // MARK: Metrics

    enum Radius {
        static let card: CGFloat = 14
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
    /// Inter — the bundled UI typeface. Weights map to static faces; if the
    /// bundle is missing, SwiftUI falls back to the system face at `size`.
    static func wv(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        let face = switch weight {
        case .bold, .heavy, .black: "Inter-Bold"
        case .semibold: "Inter-SemiBold"
        case .medium: "Inter-Medium"
        default: "Inter-Regular"
        }
        return .custom(face, size: size)
    }

    /// Page title (`Settings`, `History`).
    static let wvTitle = Font.wv(17, .semibold)
    /// Card/section title (`Transcription`, `Saved Terms`).
    static let wvHeadline = Font.wv(15, .semibold)
    /// Row title inside a card (`Launch at login`).
    static let wvRowTitle = Font.wv(14, .medium)
    /// Default body copy.
    static let wvBody = Font.wv(13)
    /// Row captions and descriptions.
    static let wvCaption = Font.wv(12.5)
    static let wvCaptionMedium = Font.wv(12.5, .medium)
    /// Tiny uppercase group labels (`USAGE`).
    static let wvOverline = Font.wv(10.5, .semibold)
    /// Keycaps render in a monospace face, matching the reference chips.
    static let wvKeycap = Font.system(size: 12, weight: .medium, design: .monospaced)
}
