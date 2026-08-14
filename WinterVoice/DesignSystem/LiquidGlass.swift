import AppKit
import SwiftUI

/// Liquid Glass adoption for macOS 26 (Tahoe).
///
/// Every surface that participates goes through `wvSurface`: on macOS 26+ it
/// renders the system Liquid Glass material clipped to the given shape; on
/// earlier systems it reproduces the classic opaque treatment (fill + hairline
/// border) exactly, so the pre-26 UI is unchanged.
extension View {

    /// A themed surface behind this view.
    ///
    /// - Parameters:
    ///   - shape: The surface shape (also used to clip the glass).
    ///   - fill: Fallback fill for macOS < 26.
    ///   - border: Fallback hairline border for macOS < 26. Glass draws its
    ///     own rim highlight, so no border is added on 26+.
    ///   - glassTint: Optional tint blended into the glass (emphasis fills,
    ///     nav pills). `nil` renders neutral glass.
    ///   - interactive: Whether the glass reacts to hover/press shimmer —
    ///     use for controls, not static cards.
    @ViewBuilder
    func wvSurface(
        in shape: some InsettableShape,
        fill: Color,
        border: Color? = nil,
        glassTint: Color? = nil,
        interactive: Bool = false
    ) -> some View {
        if #available(macOS 26.0, *) {
            glassEffect(.regular.tint(glassTint).interactive(interactive), in: shape)
        } else {
            background(fill, in: shape)
                .overlay {
                    if let border {
                        shape.strokeBorder(border, lineWidth: 1)
                    }
                }
        }
    }
}

/// The sidebar + titlebar rail background. On macOS 26+ the window behind the
/// rail is transparent, so this renders the system sidebar material — desktop
/// blurring through — washed with the theme's rail color to keep its tone.
/// Pre-26 the window stays opaque and this is the classic flat rail.
struct WVRailBackground: View {
    var body: some View {
        if #available(macOS 26.0, *) {
            BehindWindowBlur(material: .sidebar)
                .overlay(Theme.sidebar.opacity(0.25))
        } else {
            Theme.sidebar
        }
    }
}

/// An `NSVisualEffectView` blurring whatever is behind the window. SwiftUI's
/// `Material` styles only blur content within the window, so the AppKit view
/// is required for the desktop show-through.
private struct BehindWindowBlur: NSViewRepresentable {
    let material: NSVisualEffectView.Material

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = .behindWindow
        view.state = .followsWindowActiveState
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}
