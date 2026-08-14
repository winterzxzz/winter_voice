import XCTest
@testable import WinterVoice

final class OnboardingTests: XCTestCase {
    func testWizardMovesOnePermissionPageAtATimeAndStopsAtEdges() {
        var wizard = OnboardingWizard()
        XCTAssertEqual(wizard.currentPermission, .microphone)
        wizard.next()
        XCTAssertEqual(wizard.currentPermission, .inputMonitoring)
        wizard.next()
        XCTAssertEqual(wizard.currentPermission, .accessibility)
        XCTAssertTrue(wizard.isLastPage)
        wizard.next()
        XCTAssertEqual(wizard.currentPermission, .accessibility)
        wizard.back()
        XCTAssertEqual(wizard.currentPermission, .inputMonitoring)
    }

    func testProgressSelectsFirstMissingPermissionInSetupOrder() {
        let permissions = snapshot(
            microphone: .authorized,
            inputMonitoring: .denied,
            accessibility: .authorized
        )

        XCTAssertEqual(
            OnboardingProgress(permissions: permissions),
            .needsPermission(.inputMonitoring)
        )
    }

    func testProgressIsReadyOnlyWhenEveryPermissionIsAuthorized() {
        XCTAssertEqual(OnboardingProgress(permissions: authorizedSnapshot), .ready)
        XCTAssertNotEqual(
            OnboardingProgress(permissions: snapshot(accessibility: .denied)),
            .ready
        )
    }

    func testIncompletePermissionsCannotPersistCompletion() {
        let store = CompletionStoreSpy(isComplete: false)
        let subject = OnboardingInteractor(completionStore: store)

        XCTAssertFalse(subject.complete(with: snapshot(microphone: .denied)))
        XCTAssertFalse(store.isComplete)
        XCTAssertTrue(subject.shouldPresentOnLaunch(permissions: snapshot(microphone: .denied)))
    }

    func testAuthorizedCompletionPersistsAndSkipsOrdinaryLaunch() {
        let store = CompletionStoreSpy(isComplete: false)
        let subject = OnboardingInteractor(completionStore: store)

        XCTAssertTrue(subject.complete(with: authorizedSnapshot))
        XCTAssertTrue(store.isComplete)
        XCTAssertFalse(subject.shouldPresentOnLaunch(permissions: authorizedSnapshot))
    }

    func testDeferralDoesNotPersistCompletion() {
        let store = CompletionStoreSpy(isComplete: false)
        let subject = OnboardingInteractor(completionStore: store)

        subject.deferForNow()

        XCTAssertFalse(store.isComplete)
        XCTAssertTrue(subject.shouldPresentOnLaunch(permissions: authorizedSnapshot))
    }

    func testResetRestoresOnboardingEvenAfterSuccessfulCompletion() {
        let store = CompletionStoreSpy(isComplete: true)
        let subject = OnboardingInteractor(completionStore: store)

        subject.resetCompletion()

        XCTAssertFalse(store.isComplete)
        XCTAssertTrue(subject.shouldPresentOnLaunch(permissions: authorizedSnapshot))
    }

    func testCompletedSetupPresentsAgainWhenPermissionsWereRevoked() {
        let store = CompletionStoreSpy(isComplete: true)
        let subject = OnboardingInteractor(completionStore: store)

        XCTAssertFalse(subject.shouldPresentOnLaunch(permissions: authorizedSnapshot))
        XCTAssertTrue(subject.shouldPresentOnLaunch(permissions: snapshot(accessibility: .denied)))
    }

    private var authorizedSnapshot: PermissionSnapshot {
        snapshot()
    }

    private func snapshot(
        microphone: PermissionStatus = .authorized,
        inputMonitoring: PermissionStatus = .authorized,
        accessibility: PermissionStatus = .authorized
    ) -> PermissionSnapshot {
        PermissionSnapshot(
            microphone: microphone,
            inputMonitoring: inputMonitoring,
            accessibility: accessibility
        )
    }
}

private final class CompletionStoreSpy: OnboardingCompletionStoring {
    var isComplete: Bool

    init(isComplete: Bool) {
        self.isComplete = isComplete
    }
}

@MainActor
final class PermissionLifecycleTests: XCTestCase {
    func testInputMonitoringRequestPublishesInFlightAndDeniedOutcome() async {
        let manager = LifecyclePermissionManagerSpy(
            snapshots: [snapshot(inputMonitoring: .denied)],
            requestResult: .denied,
            waitsForRequest: true
        )
        let subject = makePresenter(permissionManager: manager)

        subject.request(.inputMonitoring)

        XCTAssertEqual(subject.permissionRequest, .requesting(.inputMonitoring))
        await Task.yield()
        XCTAssertEqual(manager.requestCallCount, 1)

        manager.resolveRequest(for: .inputMonitoring)
        try? await Task.sleep(nanoseconds: 20_000_000)

        XCTAssertEqual(subject.permissionRequest, .completed(.inputMonitoring, .denied))
        XCTAssertEqual(
            subject.permissionRequestMessage,
            "macOS still reports Input Monitoring as not authorized for this running WinterVoice copy. A request may not show another prompt after denial. Open System Settings to inspect the matching entry; enable it only if this copy is listed. If no WinterVoice entry appears, close other copies and relaunch this copy before trying again."
        )
    }

    func testAccessibilityRequestPublishesDeniedBuildRegistrationFeedback() async {
        let manager = LifecyclePermissionManagerSpy(
            snapshots: [snapshot(accessibility: .denied)],
            requestResult: .denied,
            waitsForRequest: true
        )
        let subject = makePresenter(permissionManager: manager)

        subject.request(.accessibility)

        XCTAssertEqual(subject.permissionRequest, .requesting(.accessibility))
        await Task.yield()
        manager.resolveRequest(for: .accessibility)
        try? await Task.sleep(nanoseconds: 20_000_000)

        XCTAssertEqual(subject.permissionRequest, .completed(.accessibility, .denied))
        XCTAssertEqual(
            subject.permissionRequestMessage,
            "macOS still reports Accessibility as not authorized for this running WinterVoice copy. Open System Settings to inspect the matching entry; enable it only if this copy is listed. If no WinterVoice entry appears, close other copies and relaunch this copy before trying again."
        )
    }

    func testActivationReconciliationPublishesSettledSnapshotToOnboarding() async {
        let denied = snapshot(inputMonitoring: .denied, accessibility: .denied)
        let allowed = snapshot()
        let manager = LifecyclePermissionManagerSpy(
            snapshots: [denied, denied, allowed],
            requestResult: .authorized
        )
        let subject = makePresenter(permissionManager: manager)
        let onboarding = OnboardingPresenter(
            dictationPresenter: subject,
            interactor: OnboardingInteractor(completionStore: CompletionStoreSpy(isComplete: false))
        )

        subject.reconcilePermissionsAfterActivation()

        XCTAssertEqual(subject.permissions, denied)
        await waitUntil { subject.permissions == allowed }

        XCTAssertEqual(subject.permissions, allowed)
        XCTAssertEqual(onboarding.progress, .ready)
    }

    func testAppActivationRoutesIntoSharedPermissionReconciliation() async {
        let denied = snapshot(inputMonitoring: .denied, accessibility: .denied)
        let allowed = snapshot()
        let manager = LifecyclePermissionManagerSpy(
            snapshots: [denied, allowed],
            requestResult: .authorized
        )
        let subject = makePresenter(permissionManager: manager)
        let onboarding = OnboardingPresenter(
            dictationPresenter: subject,
            interactor: OnboardingInteractor(completionStore: CompletionStoreSpy(isComplete: false))
        )
        let lifecycle = AppLifecycleController()
        lifecycle.didBecomeActive = { subject.reconcilePermissionsAfterActivation() }

        lifecycle.applicationDidBecomeActive(
            Notification(name: NSApplication.didBecomeActiveNotification)
        )

        await waitUntil { onboarding.progress == .ready }
        XCTAssertEqual(onboarding.progress, .ready)
    }

    func testSettledInputMonitoringGrantReconcilesHotkey() async {
        let denied = snapshot(inputMonitoring: .denied)
        let allowed = snapshot()
        let manager = LifecyclePermissionManagerSpy(
            snapshots: [denied, denied, allowed],
            requestResult: .authorized
        )
        let subject = makePresenter(permissionManager: manager)
        let hotkey = HotkeyReconciliationSpy()
        let binding = PermissionHotkeyReconciler(presenter: subject, hotkey: hotkey)
        let callsBeforeActivation = hotkey.reconcileCallCount
        XCTAssertEqual(callsBeforeActivation, 1)

        subject.reconcilePermissionsAfterActivation()

        await waitUntil {
            subject.permissions == allowed
                && hotkey.reconcileCallCount > callsBeforeActivation
        }

        XCTAssertEqual(subject.permissions, allowed)
        XCTAssertEqual(hotkey.reconcileCallCount, callsBeforeActivation + 1)
        withExtendedLifetime(binding) {}
    }

    func testCancelledRequestCannotPublishStaleOutcome() async {
        let manager = LifecyclePermissionManagerSpy(
            snapshots: [
                snapshot(inputMonitoring: .denied),
                snapshot(inputMonitoring: .denied),
                snapshot(accessibility: .authorized)
            ],
            requestResult: .denied,
            waitsForRequest: true
        )
        let subject = makePresenter(permissionManager: manager)

        subject.request(.inputMonitoring)
        await Task.yield()
        subject.request(.accessibility)
        await Task.yield()

        manager.resolveRequest(for: .inputMonitoring, with: .denied)
        manager.resolveRequest(for: .accessibility, with: .authorized)
        try? await Task.sleep(nanoseconds: 20_000_000)

        XCTAssertEqual(subject.permissionRequest, .completed(.accessibility, .authorized))
        XCTAssertEqual(subject.permissionRequestMessage, "Accessibility access is allowed.")
    }

    private func makePresenter(permissionManager: PermissionManaging) -> DictationPresenter {
        DictationPresenter(
            interactor: LifecycleDictationInteractorSpy(),
            relay: DictationStateRelay(),
            hotkeyRelay: HotkeyHealthRelay(),
            permissionManager: permissionManager,
            router: AppRouter()
        )
    }

    private func waitUntil(
        _ condition: @escaping @MainActor () -> Bool
    ) async {
        for _ in 0..<30 {
            if condition() { return }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
    }

    private func snapshot(
        microphone: PermissionStatus = .authorized,
        inputMonitoring: PermissionStatus = .authorized,
        accessibility: PermissionStatus = .authorized
    ) -> PermissionSnapshot {
        PermissionSnapshot(
            microphone: microphone,
            inputMonitoring: inputMonitoring,
            accessibility: accessibility
        )
    }
}

@MainActor
private final class LifecyclePermissionManagerSpy: PermissionManaging {
    private let snapshots: [PermissionSnapshot]
    private var nextSnapshotIndex = 0
    private let requestResult: PermissionStatus
    private let waitsForRequest: Bool
    private var requestContinuations: [AppPermission: CheckedContinuation<PermissionStatus, Never>] = [:]
    private(set) var requestCallCount = 0

    init(
        snapshots: [PermissionSnapshot],
        requestResult: PermissionStatus,
        waitsForRequest: Bool = false
    ) {
        self.snapshots = snapshots
        self.requestResult = requestResult
        self.waitsForRequest = waitsForRequest
    }

    func snapshot() -> PermissionSnapshot {
        let snapshot = snapshots[min(nextSnapshotIndex, snapshots.count - 1)]
        nextSnapshotIndex += 1
        return snapshot
    }

    func request(_ permission: AppPermission) async -> PermissionStatus {
        requestCallCount += 1
        guard waitsForRequest else { return requestResult }
        return await withCheckedContinuation { continuation in
            requestContinuations[permission] = continuation
        }
    }

    func resolveRequest(for permission: AppPermission, with status: PermissionStatus? = nil) {
        requestContinuations[permission]?.resume(returning: status ?? requestResult)
        requestContinuations[permission] = nil
    }
}

@MainActor
private final class HotkeyReconciliationSpy: HotkeyReconciling {
    private(set) var reconcileCallCount = 0

    func reconcile() {
        reconcileCallCount += 1
    }
}

@MainActor
private final class LifecycleDictationInteractorSpy: DictationInteracting {
    func beginPushToTalk() {}
    func endPushToTalk() {}
    func togglePushToTalk() {}
}
