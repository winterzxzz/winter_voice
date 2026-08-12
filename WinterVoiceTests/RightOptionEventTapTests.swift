import CoreGraphics
import XCTest
@testable import WinterVoice

@MainActor
final class RightOptionEventTapTests: XCTestCase {
    func testMissingListenPermissionRejectsEvenCreatableTap() {
        let backend = EventTapBackendSpy(installResult: true)
        let relay = HotkeyHealthRelay()
        let interactor = DictationInteractorSpy()
        let subject = RightOptionEventTap(
            interactor: interactor,
            relay: relay,
            listenAccessGranted: { false },
            backend: backend
        )

        subject.reconcile()

        XCTAssertEqual(relay.health, .permissionRequired)
        XCTAssertEqual(backend.installCallCount, 0, "A non-nil-capable tap is not evidence of Listen Event trust")
        XCTAssertEqual(backend.uninstallCallCount, 1)
    }

    func testActivationAfterPermissionGrantReplacesStalePrePermissionTap() {
        var listenAccessGranted = false
        let backend = EventTapBackendSpy(installResult: true)
        let relay = HotkeyHealthRelay()
        let subject = RightOptionEventTap(
            interactor: DictationInteractorSpy(),
            relay: relay,
            listenAccessGranted: { listenAccessGranted },
            backend: backend
        )

        subject.reconcile()
        listenAccessGranted = true
        subject.reconcile()
        subject.reconcile()

        XCTAssertEqual(backend.uninstallCallCount, 1)
        XCTAssertEqual(backend.installCallCount, 1)
        XCTAssertEqual(relay.health, .listening)
    }

    func testRightOptionEdgesAreDeduplicatedAndLeftOptionIsIgnored() {
        let backend = EventTapBackendSpy(installResult: true)
        let interactor = DictationInteractorSpy()
        let subject = RightOptionEventTap(
            interactor: interactor,
            relay: HotkeyHealthRelay(),
            listenAccessGranted: { true },
            backend: backend
        )
        subject.reconcile()

        backend.send(.modifierChanged(keyCode: 58, flags: [.maskAlternate]))
        backend.send(.modifierChanged(keyCode: 61, flags: [.maskAlternate]))
        backend.send(.modifierChanged(keyCode: 61, flags: [.maskAlternate]))
        backend.send(.modifierChanged(
            keyCode: 61,
            flags: CGEventFlags(rawValue: CGEventFlags.maskAlternate.rawValue | 0x20)
        ))

        XCTAssertEqual(interactor.beginCallCount, 1)
        XCTAssertEqual(interactor.endCallCount, 1)
    }

    func testDisabledTapReenablesAndReportsFailureWhenRecoveryFails() {
        let backend = EventTapBackendSpy(installResult: true, enableResult: false)
        let relay = HotkeyHealthRelay()
        let subject = RightOptionEventTap(
            interactor: DictationInteractorSpy(),
            relay: relay,
            listenAccessGranted: { true },
            backend: backend
        )
        subject.reconcile()

        backend.send(.disabled)

        XCTAssertEqual(backend.enableCallCount, 1)
        XCTAssertEqual(relay.health, .installationFailed)
    }
}

@MainActor
private final class EventTapBackendSpy: RightOptionEventTapBacking {
    var eventHandler: ((RightOptionEvent) -> Void)?
    private let installResult: Bool
    private let enableResult: Bool
    private(set) var installCallCount = 0
    private(set) var uninstallCallCount = 0
    private(set) var enableCallCount = 0

    init(installResult: Bool, enableResult: Bool = true) {
        self.installResult = installResult
        self.enableResult = enableResult
    }

    func install() -> Bool {
        installCallCount += 1
        return installResult
    }

    func uninstall() {
        uninstallCallCount += 1
    }

    func enable() -> Bool {
        enableCallCount += 1
        return enableResult
    }

    func send(_ event: RightOptionEvent) {
        eventHandler?(event)
    }
}

@MainActor
private final class DictationInteractorSpy: DictationInteracting {
    private(set) var beginCallCount = 0
    private(set) var endCallCount = 0

    func beginPushToTalk() { beginCallCount += 1 }
    func endPushToTalk() { endCallCount += 1 }
}
