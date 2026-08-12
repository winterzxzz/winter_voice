import XCTest
@testable import WinterVoice

final class OnboardingTests: XCTestCase {
    func testProgressSelectsFirstMissingPermissionInSetupOrder() {
        let permissions = snapshot(
            microphone: .authorized,
            speechRecognition: .denied,
            inputMonitoring: .denied,
            accessibility: .authorized
        )

        XCTAssertEqual(
            OnboardingProgress(permissions: permissions),
            .needsPermission(.speechRecognition)
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
        XCTAssertTrue(subject.shouldPresentOnLaunch)
    }

    func testAuthorizedCompletionPersistsAndSkipsOrdinaryLaunch() {
        let store = CompletionStoreSpy(isComplete: false)
        let subject = OnboardingInteractor(completionStore: store)

        XCTAssertTrue(subject.complete(with: authorizedSnapshot))
        XCTAssertTrue(store.isComplete)
        XCTAssertFalse(subject.shouldPresentOnLaunch)
    }

    func testDeferralDoesNotPersistCompletion() {
        let store = CompletionStoreSpy(isComplete: false)
        let subject = OnboardingInteractor(completionStore: store)

        subject.deferForNow()

        XCTAssertFalse(store.isComplete)
        XCTAssertTrue(subject.shouldPresentOnLaunch)
    }

    func testResetRestoresOnboardingEvenAfterSuccessfulCompletion() {
        let store = CompletionStoreSpy(isComplete: true)
        let subject = OnboardingInteractor(completionStore: store)

        subject.resetCompletion()

        XCTAssertFalse(store.isComplete)
        XCTAssertTrue(subject.shouldPresentOnLaunch)
    }

    private var authorizedSnapshot: PermissionSnapshot {
        snapshot()
    }

    private func snapshot(
        microphone: PermissionStatus = .authorized,
        speechRecognition: PermissionStatus = .authorized,
        inputMonitoring: PermissionStatus = .authorized,
        accessibility: PermissionStatus = .authorized
    ) -> PermissionSnapshot {
        PermissionSnapshot(
            microphone: microphone,
            speechRecognition: speechRecognition,
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
