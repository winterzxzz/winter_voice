import XCTest
@testable import WinterVoice

final class DictationStateMachineTests: XCTestCase {
    func testHappyPath() throws {
        var machine = DictationStateMachine()
        for state in [DictationState.preparing, .recording, .processing, .inserting, .idle] {
            try machine.transition(to: state)
        }
        XCTAssertEqual(machine.state, .idle)
    }

    func testFailureCanRecoverToIdle() throws {
        var machine = DictationStateMachine()
        try machine.transition(to: .preparing)
        try machine.transition(to: .failed(.init(message: "No", recovery: "Retry")))
        try machine.transition(to: .idle)
        XCTAssertEqual(machine.state, .idle)
    }

    func testDuplicatePressTransitionIsRejected() throws {
        var machine = DictationStateMachine()
        try machine.transition(to: .preparing)
        XCTAssertThrowsError(try machine.transition(to: .preparing))
    }
}

@MainActor
final class NoProviderDictationTests: XCTestCase {
    func testNoProviderFailsBeforePermissionsCaptureOrRecording() async {
        let relay = DictationStateRelay()
        let transcriber = UnconfiguredTranscriberSpy()
        let injector = TextInjectorSpy()
        let permissions = PermissionManagerSpy()
        let subject = DictationInteractor(
            relay: relay,
            transcriber: transcriber,
            injector: injector,
            permissions: permissions
        )

        subject.beginPushToTalk()
        await Task.yield()

        guard case .failed(let failure) = relay.state else {
            return XCTFail("Expected a visible no-provider failure, got \(relay.state)")
        }
        XCTAssertEqual(failure.message, "No transcription provider is configured.")
        XCTAssertEqual(permissions.requestCallCount, 0)
        XCTAssertEqual(injector.captureCallCount, 0)
    }
}

@MainActor
private final class UnconfiguredTranscriberSpy: SpeechTranscribing {
    func validateConfiguration() throws {
        throw DictationFailure(message: "No transcription provider is configured.", recovery: "Configure one.")
    }
    func start() async throws { try validateConfiguration() }
    func stop() async throws -> String { try validateConfiguration(); return "" }
    func cancel() {}
}

@MainActor
private final class PermissionManagerSpy: PermissionManaging {
    private(set) var requestCallCount = 0

    func snapshot() -> PermissionSnapshot {
        PermissionSnapshot(
            microphone: .notDetermined,
            inputMonitoring: .denied,
            accessibility: .denied
        )
    }

    func request(_ permission: AppPermission) async -> PermissionStatus {
        requestCallCount += 1
        return .denied
    }
}

@MainActor
private final class TextInjectorSpy: TextInjecting {
    private(set) var captureCallCount = 0

    func captureTarget() throws -> TextInsertionTarget {
        captureCallCount += 1
        return TextInsertionTarget(id: UUID())
    }

    func insert(_ text: String, into target: TextInsertionTarget) async throws {}
    func discard(_ target: TextInsertionTarget) {}
}
