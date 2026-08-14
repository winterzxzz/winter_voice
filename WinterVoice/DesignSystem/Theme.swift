import AppKit
import SwiftUI

// MARK: - Theme mode

/// The two BridgeVoice-style appearances: the black reference look and its
/// light counterpart. Selected in Settings and persisted across launches.
enum ThemeMode: String, CaseIterable, Identifiable {
    case black
    case light

    var id: String { rawValue }

    var title: String {
        switch self {
        case .black: "Black"
        case .light: "Light"
        }
    }

    var colorScheme: ColorScheme {
        self == .black ? .dark : .light
    }
}

// MARK: - Palette

/// Every color token of the design system, resolved per `ThemeMode`.
///
/// Palette and type reproduce the BridgeVoice reference: a solid rail
/// (titlebar + sidebar) beside a slightly offset content canvas, cards with
/// hairline borders, an "emphasis" language for the selected nav pill,
/// toggles, and primary buttons (white-on-black in Black, black-on-white in
/// Light), and Inter as the app-wide typeface. Every surface paints an
/// explicit color — nothing relies on the system window material — so the UI
/// reads identically regardless of the host appearance.
struct ThemePalette {

    // Canvas & surfaces
    let canvas: Color
    let sidebar: Color
    let surface: Color
    let surfaceElevated: Color
    let inset: Color

    // Borders
    let border: Color
    let borderStrong: Color
    let separator: Color

    // Text
    let textPrimary: Color
    let textSecondary: Color
    let textTertiary: Color

    // Emphasis — the high-contrast fill of primary buttons and active toggles.
    let emphasis: Color
    let textOnEmphasis: Color

    // Accents
    let accent: Color
    let accentHover: Color
    let success: Color
    let successSurface: Color
    let successBorder: Color
    let danger: Color
    let warning: Color

    // Interactive fills
    let hoverFill: Color
    let chipSelected: Color
    let chipSelectedBorder: Color
    let navPillFill: Color
    let navPillText: Color
    let toggleOffFill: Color
    let toggleKnobOff: Color
}

extension ThemePalette {

    /// The original dark reference: pure-black rail, near-black canvas, white
    /// emphasis.
    static let black = ThemePalette(
        canvas: Color(hex: 0x0A0A0A),
        sidebar: Color(hex: 0x030303),
        surface: Color(hex: 0x151517),
        surfaceElevated: Color(hex: 0x1E1E21),
        inset: Color(hex: 0x1A1A1D),
        border: Color(white: 1.0, opacity: 0.06),
        borderStrong: Color(white: 1.0, opacity: 0.13),
        separator: Color(white: 1.0, opacity: 0.06),
        textPrimary: Color(hex: 0xF7F7F8),
        textSecondary: Color(hex: 0x9C9CA3),
        textTertiary: Color(hex: 0x69696F),
        emphasis: .white,
        textOnEmphasis: Color(hex: 0x111113),
        accent: Color(hex: 0x3B82F6),
        accentHover: Color(hex: 0x2563EB),
        success: Color(hex: 0x4ADE80),
        successSurface: Color(red: 0.13, green: 0.77, blue: 0.37, opacity: 0.14),
        successBorder: Color(red: 0.13, green: 0.77, blue: 0.37, opacity: 0.28),
        danger: Color(hex: 0xF55459),
        warning: Color(hex: 0xF5A623),
        hoverFill: Color(white: 1.0, opacity: 0.06),
        chipSelected: Color(hex: 0x232326),
        chipSelectedBorder: Color(white: 1.0, opacity: 0.22),
        navPillFill: .white,
        navPillText: Color(hex: 0x111113),
        toggleOffFill: Color(white: 1.0, opacity: 0.14),
        toggleKnobOff: Color(hex: 0xA8A8AD)
    )

    /// The light reference: white rail and cards over a faint gray canvas,
    /// black emphasis, gray selected nav pill.
    static let light = ThemePalette(
        canvas: Color(hex: 0xF6F6F7),
        sidebar: .white,
        surface: .white,
        surfaceElevated: Color(hex: 0xF1F1F2),
        inset: Color(hex: 0xF4F4F5),
        border: Color(white: 0.0, opacity: 0.08),
        borderStrong: Color(white: 0.0, opacity: 0.15),
        separator: Color(white: 0.0, opacity: 0.07),
        textPrimary: Color(hex: 0x18181B),
        textSecondary: Color(hex: 0x66666E),
        textTertiary: Color(hex: 0x94949C),
        emphasis: Color(hex: 0x18181B),
        textOnEmphasis: Color(hex: 0xFAFAFA),
        accent: Color(hex: 0x3B82F6),
        accentHover: Color(hex: 0x2563EB),
        success: Color(hex: 0x16A34A),
        successSurface: Color(red: 0.13, green: 0.77, blue: 0.37, opacity: 0.14),
        successBorder: Color(red: 0.13, green: 0.77, blue: 0.37, opacity: 0.32),
        danger: Color(hex: 0xE0393E),
        warning: Color(hex: 0xC77F0A),
        hoverFill: Color(white: 0.0, opacity: 0.05),
        chipSelected: .white,
        chipSelectedBorder: Color(white: 0.0, opacity: 0.18),
        navPillFill: Color(hex: 0xE9E9EB),
        navPillText: Color(hex: 0x111113),
        toggleOffFill: Color(white: 0.0, opacity: 0.12),
        toggleKnobOff: .white
    )
}

// MARK: - Theme store

/// Owns the selected `ThemeMode`: persists it, keeps the `Theme` accessors in
/// sync, and publishes changes so window roots rebuild.
@MainActor
final class ThemeStore: ObservableObject {
    static let shared = ThemeStore()
    nonisolated static let defaultsKey = "wv.theme.mode"

    @Published var mode: ThemeMode {
        didSet {
            guard oldValue != mode else { return }
            UserDefaults.standard.set(mode.rawValue, forKey: Self.defaultsKey)
            Theme.mode = mode
        }
    }

    private init() {
        mode = Theme.mode
    }
}

// MARK: - Token accessors

/// Central design tokens for WinterVoice. Every token is an appearance-dynamic
/// color: it resolves to the Black palette under a dark appearance and the
/// Light palette under a light one. A theme switch therefore only flips the
/// window's appearance (`preferredColorScheme` + `WindowConfigurator`) and
/// AppKit re-resolves every color in place — no view-tree rebuild, so scroll
/// positions, disclosure state, and focus all survive the switch.
enum Theme {

    /// Loaded from defaults on first touch; mutated only by `ThemeStore` on
    /// the main actor.
    nonisolated(unsafe) fileprivate(set) static var mode: ThemeMode = {
        let stored = UserDefaults.standard.string(forKey: ThemeStore.defaultsKey)
        return stored.flatMap(ThemeMode.init(rawValue:)) ?? .black
    }()

    /// An `NSColor` that resolves the token against the draw-time appearance.
    private static func dynamicNSColor(_ token: KeyPath<ThemePalette, Color>) -> NSColor {
        NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return NSColor((isDark ? ThemePalette.black : ThemePalette.light)[keyPath: token])
        }
    }

    private static func dynamic(_ token: KeyPath<ThemePalette, Color>) -> Color {
        Color(nsColor: dynamicNSColor(token))
    }

    /// The window's own background — the rail color as a dynamic `NSColor`
    /// so `WindowConfigurator` keeps appearance-driven resolution.
    static var windowBackground: NSColor { dynamicNSColor(\.sidebar) }

    // MARK: Canvas & surfaces

    /// Content-area background.
    static let canvas = dynamic(\.canvas)
    /// Sidebar and titlebar rail — fuses with the window chrome.
    static let sidebar = dynamic(\.sidebar)
    /// Default card surface.
    static let surface = dynamic(\.surface)
    /// A card nested inside another card, or a pressed/elevated surface.
    static let surfaceElevated = dynamic(\.surfaceElevated)
    /// Small inset squares that hold row icons, keycaps, and inputs.
    static let inset = dynamic(\.inset)

    // MARK: Borders

    static let border = dynamic(\.border)
    static let borderStrong = dynamic(\.borderStrong)
    static let separator = dynamic(\.separator)

    // MARK: Text

    static let textPrimary = dynamic(\.textPrimary)
    static let textSecondary = dynamic(\.textSecondary)
    static let textTertiary = dynamic(\.textTertiary)

    // MARK: Emphasis

    /// High-contrast fill of primary buttons and active toggles — white in
    /// Black, near-black in Light.
    static let emphasis = dynamic(\.emphasis)
    /// Text/knob placed on the emphasis fill.
    static let textOnEmphasis = dynamic(\.textOnEmphasis)

    // MARK: Accents

    /// Primary action blue (brand mark).
    static let accent = dynamic(\.accent)
    static let accentHover = dynamic(\.accentHover)
    /// Live / active / success green.
    static let success = dynamic(\.success)
    static let successSurface = dynamic(\.successSurface)
    static let successBorder = dynamic(\.successBorder)
    /// Destructive red.
    static let danger = dynamic(\.danger)
    /// Warning amber for degraded states.
    static let warning = dynamic(\.warning)

    // MARK: Interactive fills

    /// Hovered sidebar-row fill; the selected row is a solid `navPillFill` pill.
    static let hoverFill = dynamic(\.hoverFill)
    /// Selected chip fill, with a brighter border, per reference.
    static let chipSelected = dynamic(\.chipSelected)
    static let chipSelectedBorder = dynamic(\.chipSelectedBorder)
    /// The selected sidebar row — white pill in Black, gray pill in Light.
    static let navPillFill = dynamic(\.navPillFill)
    static let navPillText = dynamic(\.navPillText)
    /// Toggle track and knob in the off state; on-state uses `emphasis`.
    static let toggleOffFill = dynamic(\.toggleOffFill)
    static let toggleKnobOff = dynamic(\.toggleKnobOff)

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
