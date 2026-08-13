import XCTest
import AppKit
@testable import WinterVoice

@MainActor
final class HistoryDictionaryTests: XCTestCase {
    func testFocusedTargetFallsBackToSystemWideAccessibilityWhenFrontmostLookupMisses() throws {
        let app = try XCTUnwrap(NSWorkspace.shared.runningApplications.first)
        let expected = FocusedAccessibilityTarget(
            application: app,
            element: AXUIElementCreateApplication(app.processIdentifier)
        )
        let subject = SystemFocusedAccessibilityTargetLocator(
            frontmostTarget: { nil },
            systemWideTarget: { expected }
        )

        let result = try XCTUnwrap(subject.focusedTarget())

        XCTAssertEqual(result.application.processIdentifier, expected.application.processIdentifier)
        XCTAssertTrue(CFEqual(try XCTUnwrap(result.element), try XCTUnwrap(expected.element)))
    }

    func testFocusedTargetFallsBackToFrontmostApplicationWhenCodexExposesNoAXElement() throws {
        let app = try XCTUnwrap(NSWorkspace.shared.runningApplications.first)
        let subject = SystemFocusedAccessibilityTargetLocator(
            frontmostTarget: { nil },
            systemWideTarget: { nil },
            frontmostApplication: { app }
        )

        let result = try XCTUnwrap(subject.focusedTarget())

        XCTAssertEqual(result.application.processIdentifier, app.processIdentifier)
        XCTAssertNil(result.element)
        XCTAssertFalse(result.isSecureField)
    }

    func testDictionaryReplacesLongerPhrasesBeforeShorterPhrases() {
        let store = DictionaryStore(persistence: DictionaryPersistenceSpy())
        try? store.add(source: "Winter Voice", replacement: "WinterVoice")
        try? store.add(source: "Voice", replacement: "speech")

        XCTAssertEqual(store.process("Winter Voice and Voice"), "WinterVoice and speech")
    }

    func testDictionaryRejectsEmptyAndDuplicateSources() {
        let store = DictionaryStore(persistence: DictionaryPersistenceSpy())
        XCTAssertThrowsError(try store.add(source: "  ", replacement: "x")) { error in
            XCTAssertEqual(error as? DictionaryStoreError, .emptySource)
        }
        XCTAssertNoThrow(try store.add(source: "Open AI", replacement: "OpenAI"))
        XCTAssertThrowsError(try store.add(source: "Open AI", replacement: "Open AI")) { error in
            XCTAssertEqual(error as? DictionaryStoreError, .duplicateSource)
        }
    }

    func testDisabledDictionaryEntryDoesNotProcessText() throws {
        let store = DictionaryStore(persistence: DictionaryPersistenceSpy())
        try store.add(source: "teh", replacement: "the")
        let entry = try XCTUnwrap(store.entries.first)

        store.setEnabled(false, for: entry)

        XCTAssertEqual(store.process("teh"), "teh")
    }

    func testHistoryNormalizesAndCapsEntries() {
        let store = HistoryStore(persistence: HistoryPersistenceSpy(), maxEntries: 2)
        store.record(text: "  first  ")
        store.record(text: "second")
        store.record(text: "third")
        store.record(text: "   ")

        XCTAssertEqual(store.entries.map(\.text), ["third", "second"])
    }

    func testJSONHistoryPersistenceRoundTrips() async throws {
        let root = temporaryRoot("history")
        defer { try? FileManager.default.removeItem(at: root) }
        let persistence = JSONHistoryPersistence(root: root)
        let entries = [HistoryEntry(createdAt: Date(timeIntervalSince1970: 42), text: "hello")]

        try await persistence.save(entries)

        let loaded = await persistence.load()
        XCTAssertEqual(loaded, entries)
    }

    func testJSONDictionaryPersistenceRoundTrips() async throws {
        let root = temporaryRoot("dictionary")
        defer { try? FileManager.default.removeItem(at: root) }
        let persistence = JSONDictionaryPersistence(root: root)
        let entries = [DictionaryEntry(source: "Winter Voice", replacement: "WinterVoice", isEnabled: false)]

        try await persistence.save(entries)

        let loaded = await persistence.load()
        XCTAssertEqual(loaded, entries)
    }

    func testDictationPipelineProcessesAndRecordsOnlyAfterInsertion() async throws {
        let relay = DictationStateRelay()
        let transcriber = PipelineTranscriberSpy()
        let injector = PipelineInjectorSpy()
        let history = HistoryRecorderSpy()
        let permissions = PipelinePermissionSpy()
        let dictionary = DictionaryStore(persistence: DictionaryPersistenceSpy())
        try dictionary.add(source: "teh", replacement: "the")
        let subject = DictationInteractor(
            relay: relay,
            transcriber: transcriber,
            injector: injector,
            permissions: permissions,
            textProcessor: dictionary,
            history: history
        )

        subject.beginPushToTalk()
        await waitUntil { relay.state == .recording }
        subject.endPushToTalk()
        await waitUntil { relay.state == .idle }

        XCTAssertEqual(injector.insertedText, "the quick fox")
        XCTAssertEqual(history.texts, ["the quick fox"])
    }

    func testDictationPipelineInsertsIntoSecureFieldWithoutRecordingHistory() async throws {
        let relay = DictationStateRelay()
        let transcriber = PipelineTranscriberSpy()
        let injector = PipelineInjectorSpy(landsInSecureField: true)
        let history = HistoryRecorderSpy()
        let permissions = PipelinePermissionSpy()
        let dictionary = DictionaryStore(persistence: DictionaryPersistenceSpy())
        try dictionary.add(source: "teh", replacement: "the")
        let subject = DictationInteractor(
            relay: relay,
            transcriber: transcriber,
            injector: injector,
            permissions: permissions,
            textProcessor: dictionary,
            history: history
        )

        subject.beginPushToTalk()
        await waitUntil { relay.state == .recording }
        subject.endPushToTalk()
        await waitUntil { relay.state == .idle }

        XCTAssertEqual(injector.insertedText, "the quick fox")
        XCTAssertTrue(history.texts.isEmpty)
    }

    func testDictationPipelineRecordsUsageTotalsOnSuccess() async throws {
        let relay = DictationStateRelay()
        let transcriber = PipelineTranscriberSpy()
        let injector = PipelineInjectorSpy()
        let usage = UsageRecorderSpy()
        let permissions = PipelinePermissionSpy()
        let subject = DictationInteractor(
            relay: relay,
            transcriber: transcriber,
            injector: injector,
            permissions: permissions,
            usage: usage
        )

        subject.beginPushToTalk()
        await waitUntil { relay.state == .recording }
        subject.endPushToTalk()
        await waitUntil { relay.state == .idle }

        XCTAssertEqual(usage.sessions.count, 1)
        XCTAssertEqual(usage.sessions.first?.words, 3, "\"teh quick fox\" is three words")
        XCTAssertGreaterThanOrEqual(usage.sessions.first?.speakingSeconds ?? -1, 0)
    }

    private func temporaryRoot(_ name: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("WinterVoice-\(name)-\(UUID().uuidString)", isDirectory: true)
    }
}

private actor HistoryPersistenceSpy: HistoryPersisting {
    func load() async -> [HistoryEntry] { [] }
    func save(_ entries: [HistoryEntry]) async throws {}
}

private actor DictionaryPersistenceSpy: DictionaryPersisting {
    func load() async -> [DictionaryEntry] { [] }
    func save(_ entries: [DictionaryEntry]) async throws {}
}

@MainActor
private final class HistoryRecorderSpy: HistoryRecording {
    private(set) var texts: [String] = []
    func record(text: String) { texts.append(text) }
}

@MainActor
private final class UsageRecorderSpy: UsageRecording {
    private(set) var sessions: [(words: Int, speakingSeconds: Double)] = []
    func recordSession(words: Int, speakingSeconds: Double) {
        sessions.append((words, speakingSeconds))
    }
}

@MainActor
private final class PipelineTranscriberSpy: SpeechTranscribing {
    func validateConfiguration() throws {}
    func start() async throws {}
    func stop() async throws -> String { "  teh quick fox  " }
    func cancel() {}
}

@MainActor
private final class PipelineInjectorSpy: TextInjecting {
    private(set) var insertedText: String?
    private let landsInSecureField: Bool

    init(landsInSecureField: Bool = false) {
        self.landsInSecureField = landsInSecureField
    }

    func captureTarget() throws -> TextInsertionTarget { TextInsertionTarget(id: UUID()) }
    func insert(_ text: String, into target: TextInsertionTarget) async throws -> InsertionOutcome {
        insertedText = text
        return InsertionOutcome(landedInSecureField: landsInSecureField)
    }
    func discard(_ target: TextInsertionTarget) {}
}

@MainActor
private final class PipelinePermissionSpy: PermissionManaging {
    func snapshot() -> PermissionSnapshot {
        PermissionSnapshot(microphone: .authorized, inputMonitoring: .authorized, accessibility: .authorized)
    }
    func request(_ permission: AppPermission) async -> PermissionStatus { .authorized }
}

@MainActor
private func waitUntil(
    timeout: TimeInterval = 1,
    condition: @escaping @MainActor () -> Bool
) async {
    let deadline = Date().addingTimeInterval(timeout)
    while !condition() && Date() < deadline {
        try? await Task.sleep(nanoseconds: 1_000_000)
    }
}
