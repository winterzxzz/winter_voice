import AppKit
import Combine
import SwiftUI

@MainActor
final class RecordingPanelController {
    private let panel: NSPanel
    private var cancellable: AnyCancellable?

    init(presenter: DictationPresenter) {
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 340, height: 86),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.contentView = NSHostingView(rootView: RecordingPanelView(presenter: presenter))
        cancellable = presenter.$state.sink { [weak self] state in self?.render(state) }
    }

    private func render(_ state: DictationState) {
        if state.isVisible {
            positionPanel()
            panel.orderFrontRegardless()
        } else {
            panel.orderOut(nil)
        }
    }

    private func positionPanel() {
        let screen = NSScreen.main ?? NSScreen.screens.first
        guard let frame = screen?.visibleFrame else { return }
        let size = panel.frame.size
        panel.setFrameOrigin(NSPoint(x: frame.midX - size.width / 2, y: frame.minY + 64))
    }
}
