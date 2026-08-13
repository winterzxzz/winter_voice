import AppKit
import Combine

enum RightOptionEvent {
    case modifierChanged(keyCode: Int64, flags: CGEventFlags)
    case keyChanged(keyCode: Int64, flags: CGEventFlags, isDown: Bool)
    case disabled
}

@MainActor
protocol RightOptionEventTapBacking: AnyObject {
    var eventHandler: ((RightOptionEvent) -> Void)? { get set }
    func install() -> Bool
    func uninstall()
    func enable() -> Bool
}

@MainActor
protocol HotkeyReconciling: AnyObject {
    func reconcile()
}

@MainActor
final class RightOptionEventTap: HotkeyReconciling {
    private weak var interactor: DictationInteracting?
    private let relay: HotkeyHealthRelay
    private let binding: HotkeyBindingStore
    private let listenAccessGranted: () -> Bool
    private let backend: RightOptionEventTapBacking
    private var isInstalled = false
    private var isPressed = false
    private var bindingCancellable: AnyCancellable?

    init(
        interactor: DictationInteracting,
        relay: HotkeyHealthRelay,
        binding: HotkeyBindingStore = HotkeyBindingStore(),
        listenAccessGranted: @escaping () -> Bool = { CGPreflightListenEventAccess() },
        backend: RightOptionEventTapBacking = SystemRightOptionEventTapBackend()
    ) {
        self.interactor = interactor
        self.relay = relay
        self.binding = binding
        self.listenAccessGranted = listenAccessGranted
        self.backend = backend
        backend.eventHandler = { [weak self] event in self?.receive(event) }
        bindingCancellable = binding.objectWillChange.sink { [weak self] _ in
            guard let self, self.isPressed else { return }
            self.isPressed = false
            self.interactor?.endPushToTalk()
        }
    }

    func reconcile() {
        guard listenAccessGranted() else {
            tearDown()
            relay.publish(.permissionRequired)
            return
        }
        guard !isInstalled else {
            relay.publish(.listening)
            return
        }
        isInstalled = backend.install()
        relay.publish(isInstalled ? .listening : .installationFailed)
    }

    func stop() {
        tearDown()
        relay.publish(.permissionRequired)
    }

    private func tearDown() {
        backend.uninstall()
        isInstalled = false
        isPressed = false
    }

    private func receive(_ event: RightOptionEvent) {
        switch event {
        case .disabled:
            let recovered = isInstalled && listenAccessGranted() && backend.enable()
            if !recovered {
                tearDown()
                relay.publish(listenAccessGranted() ? .installationFailed : .permissionRequired)
            } else {
                relay.publish(.listening)
            }
        case .modifierChanged(let keyCode, let flags):
            let selected = binding.selection
            guard selected.isModifierOnly else { return }
            let pressed = selected.matchesModifierEvent(keyCode: keyCode, flags: flags)
            updatePressed(pressed)
        case .keyChanged(let keyCode, let flags, let isDown):
            let selected = binding.selection
            guard selected.matchesKeyEvent(keyCode: keyCode, flags: flags) else { return }
            updatePressed(isDown)
        }
    }

    private func updatePressed(_ pressed: Bool) {
            guard pressed != isPressed else { return }
            isPressed = pressed
            pressed ? interactor?.beginPushToTalk() : interactor?.endPushToTalk()
    }
}

@MainActor
final class SystemRightOptionEventTapBackend: RightOptionEventTapBacking {
    var eventHandler: ((RightOptionEvent) -> Void)?
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?

    func install() -> Bool {
        uninstall()
        let mask = CGEventMask(
            (1 << CGEventType.flagsChanged.rawValue)
                | (1 << CGEventType.keyDown.rawValue)
                | (1 << CGEventType.keyUp.rawValue)
        )
        let context = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: Self.callback,
            userInfo: context
        ) else { return false }
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        self.tap = tap
        self.source = source
        return CFMachPortIsValid(tap) && CGEvent.tapIsEnabled(tap: tap)
    }

    func uninstall() {
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        if let tap { CFMachPortInvalidate(tap) }
        source = nil
        tap = nil
    }

    func enable() -> Bool {
        guard let tap, CFMachPortIsValid(tap) else { return false }
        CGEvent.tapEnable(tap: tap, enable: true)
        return CGEvent.tapIsEnabled(tap: tap)
    }

    nonisolated private static let callback: CGEventTapCallBack = { _, type, event, userInfo in
        guard let userInfo else { return Unmanaged.passUnretained(event) }
        let backend = Unmanaged<SystemRightOptionEventTapBackend>.fromOpaque(userInfo).takeUnretainedValue()
        let mapped: RightOptionEvent
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            mapped = .disabled
        } else if type == .keyDown || type == .keyUp {
            mapped = .keyChanged(
                keyCode: event.getIntegerValueField(.keyboardEventKeycode),
                flags: event.flags,
                isDown: type == .keyDown
            )
        } else {
            mapped =
            .modifierChanged(
                keyCode: event.getIntegerValueField(.keyboardEventKeycode),
                flags: event.flags
            )
        }
        MainActor.assumeIsolated { backend.eventHandler?(mapped) }
        return Unmanaged.passUnretained(event)
    }
}
