import AppKit
import SwiftUI

/// Reaches the hosting `NSWindow` and gives it the edge-to-edge dark chrome of
/// the reference UI: a transparent, hidden titlebar over a pure-black window so
/// the top strip fuses with the sidebar, plus a brand mark installed as a
/// titlebar accessory so it sits on the same line as the traffic lights.
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
        window.backgroundColor = NSColor(Theme.sidebar)
        window.appearance = NSAppearance(named: .darkAqua)
        installBrandAccessory(in: window)
    }

    private static let brandAccessoryID = NSUserInterfaceItemIdentifier("wv.titlebar.brand")

    /// Puts the logo + wordmark into the titlebar itself, to the right of the
    /// traffic lights — the reference titlebar row.
    private static func installBrandAccessory(in window: NSWindow) {
        guard !window.titlebarAccessoryViewControllers.contains(where: {
            $0.identifier == brandAccessoryID
        }) else { return }

        let controller = NSTitlebarAccessoryViewController()
        controller.identifier = brandAccessoryID
        controller.layoutAttribute = .left

        let host = NSHostingView(rootView: TitlebarBrand())
        host.frame.size = host.fittingSize
        controller.view = host
        window.addTitlebarAccessoryViewController(controller)
    }
}

/// The brand row rendered inside the titlebar accessory.
private struct TitlebarBrand: View {
    var body: some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 5.5, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Theme.accent, Color(hex: 0x1D4ED8)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 19, height: 19)
                .overlay(
                    Image(systemName: "waveform")
                        .font(.system(size: 9.5, weight: .bold))
                        .foregroundStyle(.white)
                )
            Text("WinterVoice")
                .font(.wv(13.5, .semibold))
                .foregroundStyle(Theme.textPrimary)
        }
        .padding(.leading, 8)
        .padding(.trailing, 12)
        .frame(height: 28)
    }
}

extension View {
    /// Apply the WinterVoice dark window chrome to the hosting window.
    func wvWindowChrome() -> some View {
        background(WindowConfigurator())
    }
}
