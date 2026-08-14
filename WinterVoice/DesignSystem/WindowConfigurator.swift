import AppKit
import SwiftUI

/// Reaches the hosting `NSWindow` and gives it the edge-to-edge chrome of the
/// reference UI: a transparent, hidden titlebar over a rail-colored window so
/// the top strip fuses with the sidebar, plus a brand mark installed as a
/// titlebar accessory so it sits on the same line as the traffic lights.
/// Re-applied whenever the theme changes (the window root rebuilds this view).
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
        window.appearance = NSAppearance(named: Theme.mode == .black ? .darkAqua : .aqua)
        installBrandAccessory(in: window)
    }

    private static let brandAccessoryID = NSUserInterfaceItemIdentifier("wv.titlebar.brand")

    /// Puts the logo + wordmark into the titlebar itself, to the right of the
    /// traffic lights — the reference titlebar row. Any existing accessory is
    /// rebuilt so its colors track the active theme.
    private static func installBrandAccessory(in window: NSWindow) {
        if let index = window.titlebarAccessoryViewControllers.firstIndex(where: {
            $0.identifier == brandAccessoryID
        }) {
            window.removeTitlebarAccessoryViewController(at: index)
        }

        let controller = NSTitlebarAccessoryViewController()
        controller.identifier = brandAccessoryID
        controller.layoutAttribute = .left

        let host = NSHostingView(rootView: TitlebarBrand())
        host.frame.size = host.fittingSize
        controller.view = host
        window.addTitlebarAccessoryViewController(controller)
    }
}

/// The brand row rendered inside the titlebar accessory: the sidebar toggle
/// button beside the traffic lights, then the logo and wordmark — the
/// reference titlebar layout.
private struct TitlebarBrand: View {
    @AppStorage(SidebarVisibility.key) private var sidebarVisible = true

    var body: some View {
        HStack(spacing: 10) {
            SidebarToggleButton(isOn: $sidebarVisible)
            HStack(spacing: 8) {
                WVBrandMark(size: 19)
                Text("WinterVoice")
                    .font(.wv(13.5, .semibold))
                    .foregroundStyle(Theme.textPrimary)
            }
        }
        .padding(.leading, 6)
        .padding(.trailing, 12)
        .frame(height: 28)
    }
}

/// The reference sidebar toggle: a quiet gray glyph with a hover fill.
private struct SidebarToggleButton: View {
    @Binding var isOn: Bool
    @State private var isHovering = false

    var body: some View {
        Button {
            isOn.toggle()
        } label: {
            Image(systemName: "sidebar.left")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(isHovering ? Theme.textPrimary : Theme.textSecondary)
                .frame(width: 26, height: 22)
                .background {
                    if isHovering {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Theme.hoverFill)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .onHover { isHovering = $0 }
        .help(isOn ? "Collapse sidebar" : "Expand sidebar")
    }
}

extension View {
    /// Apply the WinterVoice window chrome to the hosting window.
    func wvWindowChrome() -> some View {
        background(WindowConfigurator())
    }
}
