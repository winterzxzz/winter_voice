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

/// Visual treatment of the idle pill — the reference "Style" picker.
enum WidgetStyle: String, CaseIterable, Codable, Sendable {
    /// Logo tile plus the wordmark.
    case labeled
    /// Logo tile only.
    case icon
    /// A tiny glyph-only pill.
    case minimal
}

/// Persisted preferences for the floating widget, shared between the Settings
/// screen and the panel controller.
@MainActor
final class WidgetPreferences: ObservableObject {
    @Published var visibility: WidgetVisibility {
        didSet { defaults.set(visibility.rawValue, forKey: Self.visibilityKey) }
    }
    @Published var style: WidgetStyle {
        didSet { defaults.set(style.rawValue, forKey: Self.styleKey) }
    }
    /// Jump to the monitor the cursor is on whenever the pill is shown.
    @Published var followsCursor: Bool {
        didSet { defaults.set(followsCursor, forKey: Self.followsCursorKey) }
    }
    /// Pin the pill above the dock and ignore dragging.
    @Published var isLocked: Bool {
        didSet { defaults.set(isLocked, forKey: Self.lockedKey) }
    }

    private static let visibilityKey = "widget.visibility"
    private static let styleKey = "widget.style"
    private static let followsCursorKey = "widget.followsCursor"
    private static let lockedKey = "widget.locked"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        visibility = defaults.string(forKey: Self.visibilityKey)
            .flatMap(WidgetVisibility.init(rawValue:)) ?? .always
        style = defaults.string(forKey: Self.styleKey)
            .flatMap(WidgetStyle.init(rawValue:)) ?? .labeled
        followsCursor = defaults.bool(forKey: Self.followsCursorKey)
        isLocked = defaults.bool(forKey: Self.lockedKey)
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
    private let presenter: DictationPresenter
    private let levelMeter: AudioLevelMeter
    private var hasPositioned = false
    /// Cursor-to-origin offset captured at drag start; nil when not dragging.
    private var dragOffset: NSPoint?
    private var latestState: DictationState = .idle
    private var visibility: WidgetVisibility
    private var style: WidgetStyle
    private var cancellables = Set<AnyCancellable>()

    init(
        presenter: DictationPresenter,
        levelMeter: AudioLevelMeter,
        preferences: WidgetPreferences = WidgetPreferences(),
        defaults: UserDefaults = .standard
    ) {
        self.preferences = preferences
        self.presenter = presenter
        self.levelMeter = levelMeter
        visibility = preferences.visibility
        style = preferences.style
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
        // An NSWindow shadow around a transparent canvas would draw a visible
        // rectangle, so the pill renders shadowless.
        panel.hasShadow = false
        let hosting = NSHostingView(
            rootView: RecordingPanelView(presenter: presenter, levelMeter: levelMeter)
        )
        hostingView = hosting
        panel.contentView = hosting
        applyRootView()
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
        preferences.$style
            .sink { [weak self] style in
                self?.style = style
                self?.applyRootView()
                self?.render()
            }
            .store(in: &cancellables)
        preferences.$isLocked
            .dropFirst()
            .sink { [weak self] locked in
                guard let self else { return }
                if locked, panel.isVisible { pinAboveDock() }
            }
            .store(in: &cancellables)
    }

    /// Reassigning the root view (instead of observing preferences inside it)
    /// keeps `fittingSize` deterministic when the style changes.
    private func applyRootView() {
        hostingView.rootView = RecordingPanelView(
            presenter: presenter,
            levelMeter: levelMeter,
            style: style,
            onToggle: { [presenter] in presenter.toggleDictation() },
            onDragMoved: { [weak self] in self?.dragMoved() },
            onDragEnded: { [weak self] in self?.dragEnded() }
        )
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
        if preferences.isLocked {
            pinAboveDock()
        } else if preferences.followsCursor,
                  let target = cursorScreen(),
                  panel.screen?.frame != target.frame {
            dockBottomCenter(of: target)
        }
        panel.orderFrontRegardless()
    }

    /// The screen currently under the mouse cursor.
    private func cursorScreen() -> NSScreen? {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) }
    }

    /// Snap to the bottom-center of the relevant screen, just above the dock.
    private func pinAboveDock() {
        let screen = (preferences.followsCursor ? cursorScreen() : nil)
            ?? panel.screen ?? NSScreen.main ?? NSScreen.screens.first
        guard let screen else { return }
        dockBottomCenter(of: screen)
    }

    private func dockBottomCenter(of screen: NSScreen) {
        let frame = screen.visibleFrame
        let size = panel.frame.size
        panel.setFrameOrigin(NSPoint(x: frame.midX - size.width / 2, y: frame.minY + 12))
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

    /// Pin the window to the cursor using screen coordinates. Gesture
    /// translations are window-relative and the window moves mid-gesture,
    /// which makes delta-based dragging jitter; the global mouse location
    /// has no such feedback loop, so the pill stays glued to the cursor.
    private func dragMoved() {
        guard !preferences.isLocked else { return }
        let mouse = NSEvent.mouseLocation
        if dragOffset == nil {
            let origin = panel.frame.origin
            dragOffset = NSPoint(x: mouse.x - origin.x, y: mouse.y - origin.y)
        }
        guard let offset = dragOffset else { return }
        panel.setFrameOrigin(NSPoint(x: mouse.x - offset.x, y: mouse.y - offset.y))
    }

    private func dragEnded() {
        dragOffset = nil
        persistPosition()
    }

    private func persistPosition() {
        guard !preferences.isLocked else { return }
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
