import CoreGraphics
import XCTest
@testable import WinterVoice

@MainActor
final class RightOptionEventTapTests: XCTestCase {
    func testSelectedBindingPersistsAndImmediatelyReplacesRightOption() throws {
        let suite = "HotkeyBindingTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let binding = HotkeyBindingStore(defaults: defaults)
        let backend = EventTapBackendSpy(installResult: true)
        let interactor = DictationInteractorSpy()
        let subject = RightOptionEventTap(
            interactor: interactor,
            relay: HotkeyHealthRelay(),
            binding: binding,
            listenAccessGranted: { true },
            backend: backend
        )
        subject.reconcile()

        binding.selection = .rightControl
        backend.send(.modifierChanged(keyCode: 61, flags: [.maskAlternate]))
        backend.send(.modifierChanged(keyCode: 61, flags: []))
        backend.send(.modifierChanged(keyCode: 62, flags: [.maskControl]))
        backend.send(.modifierChanged(keyCode: 62, flags: []))

        XCTAssertEqual(interactor.beginCallCount, 1)
        XCTAssertEqual(interactor.endCallCount, 1)
        XCTAssertEqual(HotkeyBindingStore(defaults: defaults).selection, .rightControl)
    }

    func testMissingListenPermissionRejectsEvenCreatableTap() {
        let backend = EventTapBackendSpy(installResult: true)
        let relay = HotkeyHealthRelay()
        let interactor = DictationInteractorSpy()
        let subject = RightOptionEventTap(
            interactor: interactor,
            relay: relay,
            binding: makeBinding(),
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
            binding: makeBinding(),
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
            binding: makeBinding(),
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
            binding: makeBinding(),
            listenAccessGranted: { true },
            backend: backend
        )
        subject.reconcile()

        backend.send(.disabled)

        XCTAssertEqual(backend.enableCallCount, 1)
        XCTAssertEqual(relay.health, .installationFailed)
    }

    func testChangingBindingWhilePressedEndsCurrentPushToTalk() {
        let binding = makeBinding()
        let backend = EventTapBackendSpy(installResult: true)
        let interactor = DictationInteractorSpy()
        let subject = RightOptionEventTap(
            interactor: interactor,
            relay: HotkeyHealthRelay(),
            binding: binding,
            listenAccessGranted: { true },
            backend: backend
        )
        subject.reconcile()
        backend.send(.modifierChanged(keyCode: 61, flags: [.maskAlternate]))

        binding.selection = .leftControl

        XCTAssertEqual(interactor.beginCallCount, 1)
        XCTAssertEqual(interactor.endCallCount, 1)
    }

    private func makeBinding() -> HotkeyBindingStore {
        let suite = "RightOptionEventTapTests.\(UUID().uuidString)"
        let store = HotkeyBindingStore(defaults: UserDefaults(suiteName: suite)!)
        store.selection = .rightOption
        return store
    }

    func testToggleModeActsOnKeyDownEdgesOnly() {
        let binding = makeBinding()
        binding.recordingMode = .toggle
        let backend = EventTapBackendSpy(installResult: true)
        let interactor = DictationInteractorSpy()
        let subject = RightOptionEventTap(
            interactor: interactor,
            relay: HotkeyHealthRelay(),
            binding: binding,
            listenAccessGranted: { true },
            backend: backend
        )
        subject.reconcile()

        backend.send(.modifierChanged(keyCode: 61, flags: [.maskAlternate]))
        XCTAssertEqual(interactor.toggleCallCount, 1, "First key-down starts the session")
        backend.send(.modifierChanged(keyCode: 61, flags: []))
        XCTAssertEqual(interactor.toggleCallCount, 1, "Releases are ignored in toggle mode")
        backend.send(.modifierChanged(keyCode: 61, flags: [.maskAlternate]))
        XCTAssertEqual(interactor.toggleCallCount, 2, "Second key-down stops the session")
        XCTAssertEqual(interactor.beginCallCount, 0)
        XCTAssertEqual(interactor.endCallCount, 0)
    }

    func testToggleModeTearDownEndsLiveSessionWithNoKeyHeld() {
        let binding = makeBinding()
        binding.recordingMode = .toggle
        var listenAccessGranted = true
        let backend = EventTapBackendSpy(installResult: true)
        let interactor = DictationInteractorSpy()
        let subject = RightOptionEventTap(
            interactor: interactor,
            relay: HotkeyHealthRelay(),
            binding: binding,
            listenAccessGranted: { listenAccessGranted },
            backend: backend
        )
        subject.reconcile()
        backend.send(.modifierChanged(keyCode: 61, flags: [.maskAlternate]))
        backend.send(.modifierChanged(keyCode: 61, flags: []))

        listenAccessGranted = false
        subject.reconcile()

        XCTAssertEqual(interactor.endCallCount, 1, "Tap teardown must end a toggled session even though no key is held")
    }

    func testToggleModeSuspendEndsLiveSession() {
        let binding = makeBinding()
        binding.recordingMode = .toggle
        let backend = EventTapBackendSpy(installResult: true)
        let interactor = DictationInteractorSpy()
        let subject = RightOptionEventTap(
            interactor: interactor,
            relay: HotkeyHealthRelay(),
            binding: binding,
            listenAccessGranted: { true },
            backend: backend
        )
        subject.reconcile()
        backend.send(.modifierChanged(keyCode: 61, flags: [.maskAlternate]))
        backend.send(.modifierChanged(keyCode: 61, flags: []))

        subject.suspendMatching()

        XCTAssertEqual(interactor.endCallCount, 1)
        backend.send(.modifierChanged(keyCode: 61, flags: [.maskAlternate]))
        XCTAssertEqual(interactor.toggleCallCount, 1, "Suspended tap must not act on presses")
    }

    func testNewBindingDefaultsToFunctionAndSupportsRecordedCombination() {
        let suite = "HotkeyDefaultTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = HotkeyBindingStore(defaults: defaults)

        XCTAssertEqual(store.selection, .function)

        let combination = HotkeyBinding.recorded(
            keyCode: 49,
            flags: [.maskCommand, .maskShift]
        )
        XCTAssertEqual(combination.title, "⇧⌘Space")
        XCTAssertTrue(combination.matchesKeyEvent(
            keyCode: 49,
            flags: [.maskCommand, .maskShift]
        ))
    }

    func testResetToFunctionPersistsDefaultBinding() {
        let suite = "HotkeyResetTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = HotkeyBindingStore(defaults: defaults)
        store.selection = .rightOption

        store.selection = .function

        XCTAssertEqual(HotkeyBindingStore(defaults: defaults).selection, .function)
    }

    func testModifierChordRequiresAllModifiersAndEndsWhenEitherIsReleased() {
        let binding = makeBinding()
        binding.selection = .modifierChord([.maskAlternate, .maskShift])
        let backend = EventTapBackendSpy(installResult: true)
        let interactor = DictationInteractorSpy()
        let subject = RightOptionEventTap(
            interactor: interactor,
            relay: HotkeyHealthRelay(),
            binding: binding,
            listenAccessGranted: { true },
            backend: backend
        )
        subject.reconcile()

        backend.send(.modifierChanged(keyCode: 58, flags: [.maskAlternate]))
        XCTAssertEqual(interactor.beginCallCount, 0)
        backend.send(.modifierChanged(keyCode: 56, flags: [.maskAlternate, .maskShift]))
        XCTAssertEqual(interactor.beginCallCount, 1)
        backend.send(.modifierChanged(keyCode: 56, flags: [.maskAlternate]))

        XCTAssertEqual(interactor.endCallCount, 1)
        XCTAssertEqual(binding.selection.title, "⌥⇧")
    }

    func testTearDownDuringHoldEndsDictation() {
        var listenAccessGranted = true
        let backend = EventTapBackendSpy(installResult: true)
        let relay = HotkeyHealthRelay()
        let interactor = DictationInteractorSpy()
        let subject = RightOptionEventTap(
            interactor: interactor,
            relay: relay,
            binding: makeBinding(),
            listenAccessGranted: { listenAccessGranted },
            backend: backend
        )
        subject.reconcile()
        backend.send(.modifierChanged(keyCode: 61, flags: [.maskAlternate]))

        listenAccessGranted = false
        subject.reconcile()

        XCTAssertEqual(interactor.beginCallCount, 1)
        XCTAssertEqual(
            interactor.endCallCount,
            1,
            "A dictation held open by the tap must end with it; no release event can arrive once it is gone"
        )
        XCTAssertEqual(relay.health, .permissionRequired)
    }

    func testStopDuringHoldEndsDictation() {
        let backend = EventTapBackendSpy(installResult: true)
        let interactor = DictationInteractorSpy()
        let subject = RightOptionEventTap(
            interactor: interactor,
            relay: HotkeyHealthRelay(),
            binding: makeBinding(),
            listenAccessGranted: { true },
            backend: backend
        )
        subject.reconcile()
        backend.send(.modifierChanged(keyCode: 61, flags: [.maskAlternate]))

        subject.stop()

        XCTAssertEqual(interactor.endCallCount, 1)
    }

    func testFailedRecoveryDuringHoldEndsDictation() {
        let backend = EventTapBackendSpy(installResult: true, enableResult: false)
        let interactor = DictationInteractorSpy()
        let subject = RightOptionEventTap(
            interactor: interactor,
            relay: HotkeyHealthRelay(),
            binding: makeBinding(),
            listenAccessGranted: { true },
            backend: backend
        )
        subject.reconcile()
        backend.send(.modifierChanged(keyCode: 61, flags: [.maskAlternate]))

        backend.send(.disabled)

        XCTAssertEqual(interactor.endCallCount, 1)
    }

    func testRecoveredTapResyncsPhysicallyReleasedKey() {
        let backend = EventTapBackendSpy(installResult: true)
        let relay = HotkeyHealthRelay()
        let interactor = DictationInteractorSpy()
        let subject = RightOptionEventTap(
            interactor: interactor,
            relay: relay,
            binding: makeBinding(),
            listenAccessGranted: { true },
            physicallyPressed: { _ in false },
            backend: backend
        )
        subject.reconcile()
        backend.send(.modifierChanged(keyCode: 61, flags: [.maskAlternate]))

        backend.send(.disabled)

        XCTAssertEqual(relay.health, .listening)
        XCTAssertEqual(
            interactor.endCallCount,
            1,
            "A release missed while the tap was disabled must be synthesized from physical key state"
        )

        backend.send(.modifierChanged(keyCode: 61, flags: [.maskAlternate]))
        XCTAssertEqual(interactor.beginCallCount, 2)
    }

    func testRecoveredTapKeepsHeldKeyPressed() {
        let backend = EventTapBackendSpy(installResult: true)
        let interactor = DictationInteractorSpy()
        let subject = RightOptionEventTap(
            interactor: interactor,
            relay: HotkeyHealthRelay(),
            binding: makeBinding(),
            listenAccessGranted: { true },
            physicallyPressed: { _ in true },
            backend: backend
        )
        subject.reconcile()
        backend.send(.modifierChanged(keyCode: 61, flags: [.maskAlternate]))

        backend.send(.disabled)
        XCTAssertEqual(interactor.endCallCount, 0, "A physically held key keeps the dictation running")

        backend.send(.modifierChanged(keyCode: 61, flags: []))
        XCTAssertEqual(interactor.endCallCount, 1)
    }

    func testSuspendMatchingIgnoresEventsAndEndsInFlightPress() {
        let backend = EventTapBackendSpy(installResult: true)
        let interactor = DictationInteractorSpy()
        let subject = RightOptionEventTap(
            interactor: interactor,
            relay: HotkeyHealthRelay(),
            binding: makeBinding(),
            listenAccessGranted: { true },
            backend: backend
        )
        subject.reconcile()
        backend.send(.modifierChanged(keyCode: 61, flags: [.maskAlternate]))

        subject.suspendMatching()
        XCTAssertEqual(interactor.endCallCount, 1)

        backend.send(.modifierChanged(keyCode: 61, flags: [.maskAlternate]))
        XCTAssertEqual(interactor.beginCallCount, 1, "A suspended tap must not begin dictation")

        subject.resumeMatching()
        backend.send(.modifierChanged(keyCode: 61, flags: [.maskAlternate]))
        XCTAssertEqual(interactor.beginCallCount, 2)
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
    private(set) var toggleCallCount = 0

    func beginPushToTalk() { beginCallCount += 1 }
    func endPushToTalk() { endCallCount += 1 }
    func togglePushToTalk() { toggleCallCount += 1 }
}
