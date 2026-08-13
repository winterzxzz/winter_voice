import AppKit
import Combine
import SwiftUI

@MainActor
final class RecordingPanelController {
    private let panel: NSPanel
    private var cancellable: AnyCancellable?

    init(presenter: DictationPresenter, levelMeter: AudioLevelMeter) {
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 150),
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
        // The SwiftUI pill draws its own shadow; an NSWindow shadow around a
        // transparent canvas would draw a visible rectangle.
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.contentView = NSHostingView(
            rootView: RecordingPanelView(presenter: presenter, levelMeter: levelMeter)
        )
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
        panel.setFrameOrigin(NSPoint(x: frame.midX - size.width / 2, y: frame.minY + 20))
    }
}
