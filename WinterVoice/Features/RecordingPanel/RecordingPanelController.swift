import AppKit
import Combine
import SwiftUI

@MainActor
final class RecordingPanelController {
    private static let originXKey = "recordingPanel.origin.x"
    private static let originYKey = "recordingPanel.origin.y"

    private let panel: NSPanel
    private let hostingView: NSHostingView<RecordingPanelView>
    private let defaults: UserDefaults
    private var hasPositioned = false
    private var cancellable: AnyCancellable?

    init(
        presenter: DictationPresenter,
        levelMeter: AudioLevelMeter,
        defaults: UserDefaults = .standard
    ) {
        self.defaults = defaults
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 120, height: 80),
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
        let view = RecordingPanelView(presenter: presenter, levelMeter: levelMeter)
        let hosting = NSHostingView(rootView: view)
        hostingView = hosting
        panel.contentView = hosting
        hosting.rootView = RecordingPanelView(
            presenter: presenter,
            levelMeter: levelMeter,
            onToggle: { presenter.toggleDictation() },
            onDragDelta: { [weak self] delta in self?.moveBy(delta) },
            onDragEnded: { [weak self] in self?.persistPosition() }
        )
        cancellable = presenter.$state.sink { [weak self] _ in self?.render() }
    }

    private func render() {
        // The widget is always on screen: idle shows the compact pill.
        fitToContent()
        if !hasPositioned {
            positionInitially()
            hasPositioned = true
        }
        panel.orderFrontRegardless()
    }

    private func fitToContent() {
        let size = hostingView.fittingSize
        guard size.width > 0, size.height > 0 else { return }
        // Keep the pill anchored at its bottom-center while the size changes.
        let anchor = NSPoint(x: panel.frame.midX, y: panel.frame.minY)
        panel.setContentSize(size)
        panel.setFrameOrigin(NSPoint(x: anchor.x - size.width / 2, y: anchor.y))
    }

    private func positionInitially() {
        if let saved = savedOrigin(), originIsVisible(saved) {
            panel.setFrameOrigin(saved)
            return
        }
        let screen = NSScreen.main ?? NSScreen.screens.first
        guard let frame = screen?.visibleFrame else { return }
        let size = panel.frame.size
        panel.setFrameOrigin(NSPoint(x: frame.midX - size.width / 2, y: frame.minY + 12))
    }

    private func moveBy(_ delta: CGSize) {
        // SwiftUI drag deltas are y-down; AppKit origins are y-up.
        let origin = panel.frame.origin
        panel.setFrameOrigin(NSPoint(x: origin.x + delta.width, y: origin.y - delta.height))
    }

    private func persistPosition() {
        defaults.set(Double(panel.frame.origin.x), forKey: Self.originXKey)
        defaults.set(Double(panel.frame.origin.y), forKey: Self.originYKey)
    }

    private func savedOrigin() -> NSPoint? {
        guard defaults.object(forKey: Self.originXKey) != nil,
              defaults.object(forKey: Self.originYKey) != nil else { return nil }
        return NSPoint(
            x: defaults.double(forKey: Self.originXKey),
            y: defaults.double(forKey: Self.originYKey)
        )
    }

    private func originIsVisible(_ origin: NSPoint) -> Bool {
        NSScreen.screens.contains { screen in
            screen.visibleFrame.insetBy(dx: -40, dy: -40).contains(origin)
        }
    }
}
