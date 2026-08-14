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
