import Foundation
import XCTest
@testable import WinterVoice

@MainActor
final class TranscriptionSettingsControllerTests: XCTestCase {
    func testTestConnectionDoesNotPersistDraftOrKey() async throws {
        let suite = "TranscriptionSettingsControllerTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let credentials = CredentialStoreSpy()
        let store = ProviderConfigurationStore(defaults: defaults, credentials: credentials)
        try store.saveRemote(savedConfiguration, apiKey: "stored-key")
        let tester = ConnectionTesterSpy()
        tester.failure = DictationFailure(message: "Remote authentication failed.", recovery: "Check the API key stored in Keychain.")
        let subject = TranscriptionSettingsController(configuration: store, connectionTester: tester)
        subject.loadRemoteDraft()
        subject.baseURL = "https://draft.example/v1"
        subject.remoteModel = "draft-model"
        subject.apiKey = "typed-key"

        subject.testRemoteConnection()
        await waitUntil { subject.remoteResult?.hasPrefix("Testing") == false }

        XCTAssertEqual(subject.remoteResult, "Remote authentication failed.")
        XCTAssertEqual(store.remote, savedConfiguration, "Testing must not replace the saved configuration")
        XCTAssertEqual(credentials.value, "stored-key", "Testing must not write the typed key to the credential store")
        XCTAssertFalse(defaults.dictionaryRepresentation().values.contains { "\($0)".contains("draft.example") })
        let restored = ProviderConfigurationStore(defaults: defaults, credentials: credentials)
        XCTAssertEqual(restored.remote, savedConfiguration, "Testing must not persist the draft to UserDefaults")
        XCTAssertEqual(tester.requests.count, 1)
        XCTAssertEqual(tester.requests.first?.configuration.baseURL, "https://draft.example/v1")
        XCTAssertEqual(tester.requests.first?.configuration.model, "draft-model")
        XCTAssertEqual(tester.requests.first?.apiKey, "typed-key")
    }

    func testTestConnectionUsesStoredKeyWhenFieldEmpty() async throws {
        let suite = "TranscriptionSettingsControllerTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let credentials = CredentialStoreSpy()
        let store = ProviderConfigurationStore(defaults: defaults, credentials: credentials)
        try store.saveRemote(savedConfiguration, apiKey: "stored-key")
        let tester = ConnectionTesterSpy()
        let subject = TranscriptionSettingsController(configuration: store, connectionTester: tester)
        subject.loadRemoteDraft()
        subject.baseURL = "https://draft.example/v1"
        subject.remoteModel = "draft-model"
        XCTAssertTrue(subject.apiKey.isEmpty)

        subject.testRemoteConnection()
        await waitUntil { subject.remoteResult?.hasPrefix("Testing") == false }

        XCTAssertEqual(tester.requests.count, 1)
        XCTAssertEqual(tester.requests.first?.configuration, subject.draft)
        XCTAssertEqual(tester.requests.first?.apiKey, "stored-key", "An empty key field falls back to the stored credential")
    }

    func testTestConnectionInvalidDraftFailsSynchronouslyWithoutNetwork() async throws {
        let suite = "TranscriptionSettingsControllerTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = ProviderConfigurationStore(defaults: defaults, credentials: CredentialStoreSpy())
        let tester = ConnectionTesterSpy()
        let subject = TranscriptionSettingsController(configuration: store, connectionTester: tester)
        subject.remoteModel = "m"
        subject.baseURL = "http://public.example"

        subject.testRemoteConnection()

        XCTAssertEqual(subject.remoteResult, "That remote URL is not allowed.")
        for _ in 0..<10 { await Task.yield() }
        XCTAssertTrue(tester.requests.isEmpty, "Invalid drafts must be rejected before any probe is sent")
    }

    func testSaveRemotePersistsAndClearsKeyField() throws {
        let suite = "TranscriptionSettingsControllerTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let credentials = CredentialStoreSpy()
        let store = ProviderConfigurationStore(defaults: defaults, credentials: credentials)
        let subject = TranscriptionSettingsController(configuration: store, connectionTester: ConnectionTesterSpy())
        subject.baseURL = "https://new.example/v1"
        subject.remoteModel = "new-model"
        subject.apiKey = "fresh-key"

        subject.saveRemote()

        XCTAssertEqual(store.remote, RemoteProviderConfiguration(baseURL: "https://new.example/v1", model: "new-model"))
        XCTAssertEqual(credentials.value, "fresh-key")
        XCTAssertEqual(subject.apiKey, "", "The key field must clear once the credential reaches its store")
        XCTAssertEqual(subject.remoteResult, "Configuration saved.")
        let restored = ProviderConfigurationStore(defaults: defaults, credentials: credentials)
        XCTAssertEqual(restored.remote.baseURL, "https://new.example/v1")
    }

    func testTestConnectionSuccessMessageDoesNotClaimSave() async throws {
        let suite = "TranscriptionSettingsControllerTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = ProviderConfigurationStore(defaults: defaults, credentials: CredentialStoreSpy())
        let tester = ConnectionTesterSpy()
        let subject = TranscriptionSettingsController(configuration: store, connectionTester: tester)
        subject.baseURL = "https://draft.example/v1"
        subject.remoteModel = "draft-model"

        subject.testRemoteConnection()
        await waitUntil { subject.remoteResult?.hasPrefix("Testing") == false }

        let result = try XCTUnwrap(subject.remoteResult)
        XCTAssertTrue(result.hasPrefix("Connected successfully"), "Unexpected result: \(result)")
        XCTAssertNotEqual(result, "Configuration saved.", "A successful probe must not read as a completed save")
    }
}

private let savedConfiguration = RemoteProviderConfiguration(
    baseURL: "https://saved.example/v1",
    model: "saved"
)

@MainActor
private final class ConnectionTesterSpy: RemoteConnectionTesting {
    private(set) var requests: [(configuration: RemoteProviderConfiguration, apiKey: String?)] = []
    var failure: DictationFailure?

    func test(configuration: RemoteProviderConfiguration, apiKey: String?) async throws {
        requests.append((configuration: configuration, apiKey: apiKey))
        if let failure { throw failure }
    }
}

private final class CredentialStoreSpy: CredentialStoring {
    var value: String?
    var deleteError: Error?
    init(value: String? = nil, deleteError: Error? = nil) {
        self.value = value
        self.deleteError = deleteError
    }
    func read() throws -> String? { value }
    func write(_ value: String) throws { self.value = value }
    func delete() throws {
        if let deleteError { throw deleteError }
        value = nil
    }
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
