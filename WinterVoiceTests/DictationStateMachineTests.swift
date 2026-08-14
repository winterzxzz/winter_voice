import Foundation
import XCTest
import Combine
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

    func testIdleCanFailDirectlyWithoutPreparingHop() throws {
        let failure = DictationFailure(message: "No provider", recovery: "Configure one")
        var machine = DictationStateMachine()
        try machine.transition(to: .failed(failure))
        XCTAssertEqual(machine.state, .failed(failure))
    }

    func testTransitionTableAllowsDirectIdleFailureButNotRecordingToIdle() {
        let failure = DictationFailure(message: "m", recovery: "r")
        let legal: [(DictationState, DictationState)] = [
            (.idle, .failed(failure)),
            (.failed(failure), .idle)
        ]
        let illegal: [(DictationState, DictationState)] = [
            (.recording, .idle),
            (.idle, .recording)
        ]
        for (from, to) in legal {
            XCTAssertTrue(DictationStateMachine.canTransition(from: from, to: to), "\(from) → \(to) must be legal")
        }
        for (from, to) in illegal {
            XCTAssertFalse(DictationStateMachine.canTransition(from: from, to: to), "\(from) → \(to) must stay illegal")
        }
    }
}

@MainActor
final class DictationInteractorFlowTests: XCTestCase {
    func testTargetIsCapturedOnceBeforeTranscriberStartAndAnyPermissionRequest() async {
        let log = EventLog()
        let relay = DictationStateRelay()
        let transcriber = ReadyTranscriberSpy(log: log)
        let injector = TextInjectorSpy(log: log)
        let permissions = AuthorizedPermissionManagerSpy(log: log)
        let subject = DictationInteractor(
            relay: relay,
            transcriber: transcriber,
            injector: injector,
            permissions: permissions
        )

        subject.beginPushToTalk()
        await waitUntil { relay.state == .recording }

        XCTAssertEqual(relay.state, .recording)
        XCTAssertEqual(injector.captureCallCount, 1)
        XCTAssertEqual(
            log.events,
            ["injector.capture", "transcriber.start"],
            "The focused field must be captured exactly once, before transcriber.start and before any permission request"
        )
        XCTAssertEqual(permissions.requestCallCount, 0)
    }

    func testStopFailureCancelsTranscriberDiscardsTargetAndAutoResetsToIdle() async {
        let relay = DictationStateRelay()
        let transcriber = ReadyTranscriberSpy()
        transcriber.stopError = DictationFailure(message: "Transcription crashed.", recovery: "Try again.")
        let injector = TextInjectorSpy()
        let permissions = AuthorizedPermissionManagerSpy()
        let subject = DictationInteractor(
            relay: relay,
            transcriber: transcriber,
            injector: injector,
            permissions: permissions,
            failureResetDelay: .milliseconds(50)
        )

        subject.beginPushToTalk()
        await waitUntil { relay.state == .recording }
        subject.endPushToTalk()
        await waitUntil { isFailed(relay.state) }

        guard case .failed(let failure) = relay.state else {
            return XCTFail("Expected the stop failure to surface, got \(relay.state)")
        }
        XCTAssertEqual(failure.message, "Transcription crashed.")
        XCTAssertEqual(transcriber.cancelCallCount, 1)
        XCTAssertEqual(injector.discardedTargets, injector.capturedTargets, "The captured target must be discarded on failure")
        XCTAssertTrue(injector.insertedTexts.isEmpty)

        await waitUntil { relay.state == .idle }
        XCTAssertEqual(relay.state, .idle, "A failure must auto-reset to idle after failureResetDelay")
    }

    func testPressWhileFailedImmediatelyStartsNewAttempt() async {
        let relay = DictationStateRelay()
        let transcriber = ReadyTranscriberSpy()
        transcriber.stopError = DictationFailure(message: "Transcription crashed.", recovery: "Try again.")
        let injector = TextInjectorSpy()
        let permissions = AuthorizedPermissionManagerSpy()
        // A deliberately long reset delay: reaching .recording within the wait
        // budget proves the new press did not depend on the auto-reset timer.
        let subject = DictationInteractor(
            relay: relay,
            transcriber: transcriber,
            injector: injector,
            permissions: permissions,
            failureResetDelay: .seconds(60)
        )

        subject.beginPushToTalk()
        await waitUntil { relay.state == .recording }
        subject.endPushToTalk()
        await waitUntil { isFailed(relay.state) }
        guard isFailed(relay.state) else {
            return XCTFail("Expected the first attempt to fail, got \(relay.state)")
        }

        transcriber.stopError = nil
        subject.beginPushToTalk()

        XCTAssertEqual(relay.state, .preparing, "A press during .failed must immediately dismiss the failure and begin preparing")
        await waitUntil { relay.state == .recording }
        XCTAssertEqual(relay.state, .recording)
    }

    func testPressDuringProcessingCancelsTranscriptionAndSurfacesCanceledFailure() async {
        let relay = DictationStateRelay()
        let transcriber = GatedStopTranscriberSpy()
        let injector = TextInjectorSpy()
        let permissions = AuthorizedPermissionManagerSpy()
        let subject = DictationInteractor(
            relay: relay,
            transcriber: transcriber,
            injector: injector,
            permissions: permissions,
            failureResetDelay: .milliseconds(50)
        )

        subject.beginPushToTalk()
        await waitUntil { relay.state == .recording }
        subject.endPushToTalk()
        await waitUntil { relay.state == .processing }
        XCTAssertEqual(relay.state, .processing)

        subject.beginPushToTalk()

        await waitUntil { isFailed(relay.state) }
        guard case .failed(let failure) = relay.state else {
            return XCTFail("Expected the canceled transcription to surface, got \(relay.state)")
        }
        XCTAssertEqual(failure.message, "Transcription canceled.")
        XCTAssertEqual(transcriber.cancelCallCount, 2, "The press cancels once; fail() cancels defensively again")
        XCTAssertTrue(injector.insertedTexts.isEmpty, "A canceled transcription must not insert or record anything")
        await waitUntil { relay.state == .idle }
        XCTAssertEqual(relay.state, .idle)
    }

    func testQuickTapReleasedWhilePreparingAutoFinishesDictation() async {
        let relay = DictationStateRelay()
        let transcriber = GatedStartTranscriberSpy()
        let injector = TextInjectorSpy()
        let permissions = AuthorizedPermissionManagerSpy()
        let subject = DictationInteractor(
            relay: relay,
            transcriber: transcriber,
            injector: injector,
            permissions: permissions,
            failureResetDelay: .milliseconds(50)
        )

        subject.beginPushToTalk()
        XCTAssertEqual(relay.state, .preparing)
        subject.endPushToTalk()
        XCTAssertEqual(relay.state, .preparing, "A release during preparation must defer the finish, not abort it")

        await waitUntil { transcriber.isAwaitingStart }
        XCTAssertTrue(transcriber.isAwaitingStart, "The interactor should be held in .preparing at transcriber.start")
        transcriber.releaseStart()

        await waitUntil { relay.state == .idle }
        XCTAssertEqual(relay.state, .idle)
        XCTAssertEqual(injector.insertedTexts, ["tapped text"], "A quick tap must still insert once recording becomes possible")
    }
}

@MainActor
final class NoProviderDictationTests: XCTestCase {
    func testNoProviderFailsDirectlyWithoutPreparingPermissionsOrCapture() {
        let relay = DictationStateRelay()
        let transcriber = UnconfiguredTranscriberSpy()
        let injector = TextInjectorSpy()
        let permissions = PermissionManagerSpy()
        var published: [DictationState] = []
        let observer = relay.$state.sink { published.append($0) }
        let subject = DictationInteractor(
            relay: relay,
            transcriber: transcriber,
            injector: injector,
            permissions: permissions,
            failureResetDelay: .milliseconds(50)
        )

        subject.beginPushToTalk()

        withExtendedLifetime(observer) {}
        guard case .failed(let failure) = relay.state else {
            return XCTFail("Expected a visible no-provider failure, got \(relay.state)")
        }
        XCTAssertEqual(failure.message, "No transcription provider is configured.")
        XCTAssertFalse(published.contains(.preparing), "Sync validation failure must go straight .idle → .failed")
        XCTAssertEqual(published.last, .failed(failure))
        XCTAssertEqual(permissions.requestCallCount, 0)
        XCTAssertEqual(injector.captureCallCount, 0)
    }

    func testRealTranscriberWithoutLocalModelFailsWithProductionMessage() throws {
        let suite = "NoLocalModelDictationTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        assertRealTranscriberFailsDirectly(
            transcriber: makeRealTranscriber(mode: .local, defaults: defaults),
            expectedMessage: "No local model is selected."
        )
    }

    func testRealTranscriberWithUnconfiguredRemoteFailsWithProductionMessage() throws {
        let suite = "UnconfiguredRemoteDictationTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        assertRealTranscriberFailsDirectly(
            transcriber: makeRealTranscriber(mode: .remote, defaults: defaults),
            expectedMessage: "Remote transcription provider is not configured."
        )
    }

    private func makeRealTranscriber(mode: ProviderMode, defaults: UserDefaults) -> ConfiguredTranscriber {
        let store = ProviderConfigurationStore(defaults: defaults, credentials: CredentialStoreSpy())
        store.mode = mode
        let models = ModelManager(
            root: FileManager.default.temporaryDirectory
                .appendingPathComponent("WinterVoice-RealProviderTests-\(UUID().uuidString)", isDirectory: true)
        )
        return ConfiguredTranscriber(
            recorder: AudioRecorderSpy(),
            configuration: store,
            models: models,
            localRuntime: LocalRuntimeSpy()
        )
    }

    private func assertRealTranscriberFailsDirectly(
        transcriber: ConfiguredTranscriber,
        expectedMessage: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let relay = DictationStateRelay()
        let injector = TextInjectorSpy()
        let permissions = PermissionManagerSpy()
        var published: [DictationState] = []
        let observer = relay.$state.sink { published.append($0) }
        let subject = DictationInteractor(
            relay: relay,
            transcriber: transcriber,
            injector: injector,
            permissions: permissions,
            failureResetDelay: .milliseconds(50)
        )

        subject.beginPushToTalk()

        withExtendedLifetime(observer) {}
        guard case .failed(let failure) = relay.state else {
            return XCTFail("Expected the production failure, got \(relay.state)", file: file, line: line)
        }
        XCTAssertEqual(failure.message, expectedMessage, file: file, line: line)
        XCTAssertFalse(published.contains(.preparing), "Unready providers must fail without a .preparing hop", file: file, line: line)
        XCTAssertEqual(permissions.requestCallCount, 0, file: file, line: line)
        XCTAssertEqual(injector.captureCallCount, 0, file: file, line: line)
    }

    func testCopyModeDeliversToClipboardWithoutTouchingTheFocusedField() async {
        let relay = DictationStateRelay()
        let transcriber = ReadyTranscriberSpy()
        transcriber.stopResult = "copied words"
        let injector = TextInjectorSpy()
        let copier = TranscriptCopierSpy()
        let subject = DictationInteractor(
            relay: relay,
            transcriber: transcriber,
            injector: injector,
            // Accessibility is denied: copy mode must not require it.
            permissions: MicOnlyPermissionManagerSpy(),
            behavior: CopyModeBehaviorStub(),
            transcriptCopier: copier
        )

        subject.beginPushToTalk()
        await waitUntil { relay.state == .recording }
        subject.endPushToTalk()
        await waitUntil { relay.state == .idle && !copier.copiedTexts.isEmpty }

        XCTAssertEqual(copier.copiedTexts, ["copied words"])
        XCTAssertEqual(injector.captureCallCount, 0, "Copy mode must never capture the focused field")
        XCTAssertTrue(injector.insertedTexts.isEmpty, "Copy mode must never inject text")
    }

    func testCopyModeFailedCopySurfacesAsDictationFailure() async {
        let relay = DictationStateRelay()
        let transcriber = ReadyTranscriberSpy()
        let copier = TranscriptCopierSpy()
        copier.result = false
        let subject = DictationInteractor(
            relay: relay,
            transcriber: transcriber,
            injector: TextInjectorSpy(),
            permissions: MicOnlyPermissionManagerSpy(),
            behavior: CopyModeBehaviorStub(),
            transcriptCopier: copier,
            failureResetDelay: .milliseconds(50)
        )

        subject.beginPushToTalk()
        await waitUntil { relay.state == .recording }
        subject.endPushToTalk()
        await waitUntil { isFailed(relay.state) }

        guard case .failed(let failure) = relay.state else {
            return XCTFail("Expected the copy failure to surface, got \(relay.state)")
        }
        XCTAssertEqual(failure.message, "Could not copy the transcript.")
    }
}

@MainActor
private final class CopyModeBehaviorStub: DictationBehaviorProviding {
    let copiesInsteadOfInserting = true
}

@MainActor
private final class TranscriptCopierSpy: TranscriptCopying {
    private(set) var copiedTexts: [String] = []
    var result = true

    func copy(_ text: String) -> Bool {
        copiedTexts.append(text)
        return result
    }
}

/// Microphone and Input Monitoring granted, Accessibility denied — the exact
/// posture copy mode must work in.
@MainActor
private final class MicOnlyPermissionManagerSpy: PermissionManaging {
    func snapshot() -> PermissionSnapshot {
        PermissionSnapshot(microphone: .authorized, inputMonitoring: .authorized, accessibility: .denied)
    }

    func request(_ permission: AppPermission) async -> PermissionStatus { .authorized }
}

@MainActor
private final class EventLog {
    private(set) var events: [String] = []
    func record(_ event: String) { events.append(event) }
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
private final class ReadyTranscriberSpy: SpeechTranscribing {
    var stopError: Error?
    var stopResult = "text"
    private(set) var cancelCallCount = 0
    private let log: EventLog?

    init(log: EventLog? = nil) { self.log = log }

    func validateConfiguration() throws {}
    func start() async throws { log?.record("transcriber.start") }
    func stop() async throws -> String {
        if let stopError { throw stopError }
        return stopResult
    }
    func cancel() { cancelCallCount += 1 }
}

/// Holds the interactor in .preparing at `transcriber.start()` until the test
/// resumes it, so a release-before-recording quick tap is deterministic.
@MainActor
private final class GatedStartTranscriberSpy: SpeechTranscribing {
    private var startGate: CheckedContinuation<Void, Never>?

    var isAwaitingStart: Bool { startGate != nil }

    func validateConfiguration() throws {}
    func start() async throws {
        await withCheckedContinuation { startGate = $0 }
    }
    func releaseStart() {
        startGate?.resume()
        startGate = nil
    }
    func stop() async throws -> String { "tapped text" }
    func cancel() {}
}

/// Holds `stop()` suspended (the .processing window) until `cancel()` aborts
/// it with CancellationError, mirroring the whisper abort-callback contract.
@MainActor
private final class GatedStopTranscriberSpy: SpeechTranscribing {
    private(set) var cancelCallCount = 0
    private var stopGate: CheckedContinuation<Void, Error>?

    func validateConfiguration() throws {}
    func start() async throws {}
    func stop() async throws -> String {
        try await withCheckedThrowingContinuation { stopGate = $0 }
        return "unused"
    }
    func cancel() {
        cancelCallCount += 1
        stopGate?.resume(throwing: CancellationError())
        stopGate = nil
    }
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
private final class AuthorizedPermissionManagerSpy: PermissionManaging {
    private(set) var requestCallCount = 0
    private let log: EventLog?

    init(log: EventLog? = nil) { self.log = log }

    func snapshot() -> PermissionSnapshot {
        PermissionSnapshot(microphone: .authorized, inputMonitoring: .authorized, accessibility: .authorized)
    }

    func request(_ permission: AppPermission) async -> PermissionStatus {
        log?.record("permissions.request")
        requestCallCount += 1
        return .authorized
    }
}

@MainActor
private final class TextInjectorSpy: TextInjecting {
    private(set) var capturedTargets: [TextInsertionTarget] = []
    private(set) var insertedTexts: [String] = []
    private(set) var discardedTargets: [TextInsertionTarget] = []
    private let log: EventLog?

    init(log: EventLog? = nil) { self.log = log }

    var captureCallCount: Int { capturedTargets.count }

    func captureTarget() throws -> TextInsertionTarget {
        log?.record("injector.capture")
        let target = TextInsertionTarget(id: UUID())
        capturedTargets.append(target)
        return target
    }

    @discardableResult
    func insert(_ text: String, into target: TextInsertionTarget) async throws -> InsertionOutcome {
        log?.record("injector.insert")
        insertedTexts.append(text)
        return InsertionOutcome(landedInSecureField: false)
    }

    func discard(_ target: TextInsertionTarget) { discardedTargets.append(target) }
}

@MainActor
private final class AudioRecorderSpy: AudioRecording {
    func start() throws {}
    func stop() throws -> RecordedAudio { RecordedAudio(samples: [], sampleRate: 16_000) }
    func cancel() {}
}

private actor LocalRuntimeSpy: LocalTranscriptionRunning {
    func transcribe(_ audio: RecordedAudio, modelURL: URL, language: String?) -> String { "" }
    nonisolated func cancelActiveTranscription() {}
    func unloadContext() {}
}

private final class CredentialStoreSpy: CredentialStoring {
    var value: String?
    func read() throws -> String? { value }
    func write(_ value: String) throws { self.value = value }
    func delete() throws { value = nil }
}

private func isFailed(_ state: DictationState) -> Bool {
    if case .failed = state { return true }
    return false
}

@MainActor
private func waitUntil(
    timeout: TimeInterval = 2,
    condition: @escaping @MainActor () -> Bool
) async {
    let deadline = Date().addingTimeInterval(timeout)
    while !condition() && Date() < deadline {
        try? await Task.sleep(nanoseconds: 1_000_000)
    }
}
