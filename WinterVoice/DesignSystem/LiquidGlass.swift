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
                .overlay {
                    // The glass rim reads on dark canvases but vanishes on the
                    // light one, so surfaces keep their hairline for definition.
                    if let border {
                        shape.strokeBorder(border, lineWidth: 1)
                    }
                }
        } else {
            background(fill, in: shape)
                .overlay {
                    if let border {
                        shape.strokeBorder(border, lineWidth: 1)
                    }
                }
        }
    }

    /// Suppress macOS 26's automatic scroll-edge bar under the titlebar; the
    /// rail strip painted by `AppShellView` provides that treatment, and the
    /// system bar draws a full-width slab over it that breaks the rail fusion.
    @ViewBuilder
    func wvTopScrollEdgeEffectHidden() -> some View {
        if #available(macOS 26.0, *) {
            scrollEdgeEffectHidden(true, for: .top)
        } else {
            self
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
                .overlay(Theme.railGlassWash)
        } else {
            Theme.sidebar
        }
    }
}

/// The content pane background. On macOS 26+ the canvas color is laid as a
/// heavy wash over a behind-window blur, so the pane keeps its tone and text
/// contrast while the desktop gives it glass depth — and card `glassEffect`s
/// have a live backdrop to refract. Pre-26 it is the classic flat canvas.
struct WVCanvasBackground: View {
    var body: some View {
        if #available(macOS 26.0, *) {
            BehindWindowBlur(material: .underWindowBackground)
                .overlay(Theme.canvas.opacity(0.82))
        } else {
            Theme.canvas
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
