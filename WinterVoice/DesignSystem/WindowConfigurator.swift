import AppKit
import SwiftUI

/// Reaches the hosting `NSWindow` and gives it the edge-to-edge dark chrome the
/// reference UI uses: a transparent, hidden titlebar with a full-size content
/// view, so the sidebar and content run behind the traffic lights on a single
/// near-black canvas instead of the default gray titlebar.
struct WindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { [weak view] in
            guard let window = view?.window else { return }
            Self.apply(to: window)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    static func apply(to window: NSWindow) {
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.styleMask.insert(.fullSizeContentView)
        window.isMovableByWindowBackground = true
        window.backgroundColor = NSColor(Theme.canvas)
        window.appearance = NSAppearance(named: .darkAqua)
    }
}

extension View {
    /// Apply the WinterVoice dark window chrome to the hosting window.
    func wvWindowChrome() -> some View {
        background(WindowConfigurator())
    }
}
