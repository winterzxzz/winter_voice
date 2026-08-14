import AppKit
import Combine
import SwiftUI

/// When the floating pill is on screen — the reference "Show widget" setting.
enum WidgetVisibility: String, CaseIterable, Codable, Sendable {
    case always
    case whileRecording
    case hidden

    var title: String {
        switch self {
        case .always: "Always"
        case .whileRecording: "Recording"
        case .hidden: "Hidden"
        }
    }
}

/// Persisted preferences for the floating widget, shared between the Settings
/// screen and the panel controller.
@MainActor
final class WidgetPreferences: ObservableObject {
    @Published var visibility: WidgetVisibility {
        didSet { defaults.set(visibility.rawValue, forKey: Self.visibilityKey) }
    }

    private static let visibilityKey = "widget.visibility"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        visibility = defaults.string(forKey: Self.visibilityKey)
            .flatMap(WidgetVisibility.init(rawValue:)) ?? .always
    }
}

@MainActor
final class RecordingPanelController {
    private static let originXKey = "recordingPanel.origin.x"
    private static let originYKey = "recordingPanel.origin.y"

    private let panel: NSPanel
    private let hostingView: NSHostingView<RecordingPanelView>
    private let defaults: UserDefaults
    private let preferences: WidgetPreferences
    private var hasPositioned = false
    private var latestState: DictationState = .idle
    private var visibility: WidgetVisibility
    private var cancellables = Set<AnyCancellable>()

    init(
        presenter: DictationPresenter,
        levelMeter: AudioLevelMeter,
        preferences: WidgetPreferences = WidgetPreferences(),
        defaults: UserDefaults = .standard
    ) {
        self.preferences = preferences
        visibility = preferences.visibility
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
        presenter.$state
            .sink { [weak self] state in
                self?.latestState = state
                self?.render()
            }
            .store(in: &cancellables)
        preferences.$visibility
            .sink { [weak self] visibility in
                self?.visibility = visibility
                self?.render()
            }
            .store(in: &cancellables)
    }

    /// Bring the pill to the front without changing state — the fixed
    /// Cmd+Shift+Space shortcut. Ignored while the widget is set to Hidden.
    func showWidget() {
        guard visibility != .hidden else { return }
        present()
    }

    private func render() {
        let visible: Bool
        switch visibility {
        case .always: visible = true
        case .whileRecording: visible = latestState != .idle
        case .hidden: visible = false
        }
        guard visible else {
            panel.orderOut(nil)
            return
        }
        present()
    }

    private func present() {
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
