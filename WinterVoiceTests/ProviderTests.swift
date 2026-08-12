import Foundation
import Security
import XCTest
@testable import WinterVoice

@MainActor
final class ProviderConfigurationTests: XCTestCase {
    func testModeRemoteConfigurationAndCredentialPersistAtTheirOwnedStores() throws {
        let suite = "ProviderConfigurationTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let credentials = CredentialStoreSpy()
        let subject = ProviderConfigurationStore(defaults: defaults, credentials: credentials)

        subject.mode = .remote
        try subject.saveRemote(
            .init(baseURL: "https://host.example/v1", model: "transcriber", language: "vi"),
            apiKey: "secret"
        )
        let restored = ProviderConfigurationStore(defaults: defaults, credentials: credentials)

        XCTAssertEqual(restored.mode, .remote)
        XCTAssertEqual(restored.remote.model, "transcriber")
        XCTAssertEqual(try restored.apiKey(), "secret")
        XCTAssertFalse(defaults.dictionaryRepresentation().values.contains { "\($0)".contains("secret") })
    }

    func testProviderStatusIsSingleTruthForReadyRemoteAndBlockedLocal() throws {
        let suite = "ProviderStatusTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let credentials = CredentialStoreSpy()
        let store = ProviderConfigurationStore(defaults: defaults, credentials: credentials)
        let modelRoot = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
        defer { try? FileManager.default.removeItem(at: modelRoot) }
        let models = ModelManager(root: modelRoot)

        XCTAssertEqual(store.status(localModels: models).mode, .local)
        XCTAssertFalse(store.status(localModels: models).isReady)
        store.mode = .remote
        try store.saveRemote(.init(baseURL: "https://host.example/v1", model: "m", language: ""), apiKey: nil)
        XCTAssertTrue(store.status(localModels: models).isReady)
        XCTAssertTrue(store.status(localModels: models).readiness.detail.contains("without authentication"))
        try store.saveRemote(.init(baseURL: "https://host.example/v1", model: "m", language: ""), apiKey: "secret")
        let remote = store.status(localModels: models)
        XCTAssertTrue(remote.isReady)
        XCTAssertTrue(remote.overviewSummary.contains("Remote transcription is configured"))
        XCTAssertTrue(remote.privacySummary.contains("configured remote endpoint"))
        XCTAssertTrue(remote.readiness.detail.contains("Keychain authentication"))
    }

    func testExplicitCredentialRemovalChangesStatusAndSubsequentRequestIsUnauthenticated() async throws {
        let suite = "CredentialRemovalTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let credentials = CredentialStoreSpy()
        let store = ProviderConfigurationStore(defaults: defaults, credentials: credentials)
        let models = ModelManager(root: FileManager.default.temporaryDirectory.appendingPathComponent(suite))
        store.mode = .remote
        try store.saveRemote(.init(baseURL: "https://host.example/v1", model: "m", language: ""), apiKey: "secret")

        try store.saveRemote(store.remote, apiKey: nil)
        XCTAssertEqual(try store.apiKey(), "secret", "Blank ordinary save preserves the existing key")
        try store.removeAPIKey()

        XCTAssertFalse(store.hasAPIKey)
        XCTAssertNil(try store.apiKey())
        XCTAssertTrue(store.status(localModels: models).readiness.detail.contains("without authentication"))
        let transport = RemoteTransportSpy(status: 200, body: #"{"text":"ok"}"#)
        _ = try await RemoteTranscriptionProvider(transport: transport).transcribe(
            audio: .init(samples: [0], sampleRate: 16_000),
            configuration: store.remote,
            apiKey: try store.apiKey()
        )
        let capturedRequest = await transport.capturedRequest()
        let request = try XCTUnwrap(capturedRequest)
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
    }

    func testFailedCredentialRemovalPreservesKeyAndAuthenticatedStatus() throws {
        let suite = "CredentialRemovalFailureTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let credentials = CredentialStoreSpy(value: "secret", deleteError: TestFailure.expected)
        let store = ProviderConfigurationStore(defaults: defaults, credentials: credentials)
        let models = ModelManager(root: FileManager.default.temporaryDirectory.appendingPathComponent(suite))
        store.mode = .remote
        try store.saveRemote(.init(baseURL: "https://host.example", model: "m", language: ""), apiKey: nil)

        XCTAssertThrowsError(try store.removeAPIKey())
        XCTAssertTrue(store.hasAPIKey)
        XCTAssertEqual(try store.apiKey(), "secret")
        XCTAssertTrue(store.status(localModels: models).readiness.detail.contains("Keychain authentication"))
    }

    func testKeychainWriteUpdatesWithoutDeletingExistingCredential() throws {
        let operations = KeychainOperationsSpy(updateStatus: errSecSuccess, addStatus: errSecSuccess)
        let subject = KeychainCredentialStore(operations: operations)
        try subject.write("replacement")
        XCTAssertEqual(operations.updateCallCount, 1)
        XCTAssertEqual(operations.addCallCount, 0)
        XCTAssertEqual(operations.deleteCallCount, 0)
    }

    func testKeychainFailedUpdatePreservesExistingCredential() {
        let operations = KeychainOperationsSpy(updateStatus: errSecAuthFailed, addStatus: errSecSuccess)
        let subject = KeychainCredentialStore(operations: operations)
        XCTAssertThrowsError(try subject.write("replacement"))
        XCTAssertEqual(operations.addCallCount, 0)
        XCTAssertEqual(operations.deleteCallCount, 0)
    }

    func testKeychainAddsOnlyWhenItemIsNotFound() throws {
        let operations = KeychainOperationsSpy(updateStatus: errSecItemNotFound, addStatus: errSecSuccess)
        let subject = KeychainCredentialStore(operations: operations)
        try subject.write("first")
        XCTAssertEqual(operations.updateCallCount, 1)
        XCTAssertEqual(operations.addCallCount, 1)
        XCTAssertEqual(operations.deleteCallCount, 0)
    }
}

final class RemoteProviderTests: XCTestCase {
    func testEndpointAllowsHTTPSAndExplicitPrivateHTTPOnly() throws {
        XCTAssertEqual(
            try RemoteTranscriptionProvider.endpoint(for: .init(baseURL: "https://host.example/v1", model: "m", language: "")).path,
            "/v1/audio/transcriptions"
        )
        XCTAssertNoThrow(try RemoteTranscriptionProvider.endpoint(for: .init(baseURL: "http://192.168.1.4:9000/v1", model: "m", language: "")))
        XCTAssertThrowsError(try RemoteTranscriptionProvider.endpoint(for: .init(baseURL: "http://public.example/v1", model: "m", language: "")))
        XCTAssertThrowsError(try RemoteTranscriptionProvider.endpoint(for: .init(baseURL: "https://user:password@host.example/v1", model: "m", language: "")))
        XCTAssertThrowsError(try RemoteTranscriptionProvider.endpoint(for: .init(baseURL: "https://host.example/v1#secret", model: "m", language: "")))
        let queryEndpoint = try RemoteTranscriptionProvider.endpoint(for: .init(baseURL: "https://host.example/v1?deployment=a", model: "m", language: ""))
        XCTAssertEqual(queryEndpoint.query, "deployment=a", "Non-secret endpoint query parameters are deliberately preserved")
    }

    func testMultipartRequestAndStandardTextResponse() async throws {
        let transport = RemoteTransportSpy(status: 200, body: #"{"text":"hello"}"#)
        let subject = RemoteTranscriptionProvider(transport: transport)
        let configuration = RemoteProviderConfiguration(baseURL: "https://host.example/v1", model: "model-a", language: "vi")

        let text = try await subject.transcribe(
            audio: .init(samples: [0, 0.5], sampleRate: 16_000),
            configuration: configuration,
            apiKey: "test-key"
        )

        XCTAssertEqual(text, "hello")
        let capturedRequest = await transport.request
        let request = try XCTUnwrap(capturedRequest)
        XCTAssertEqual(request.url?.path, "/v1/audio/transcriptions")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-key")
        let body = String(decoding: try XCTUnwrap(request.httpBody), as: UTF8.self)
        XCTAssertTrue(body.contains("name=\"model\"\r\n\r\nmodel-a"))
        XCTAssertTrue(body.contains("name=\"language\"\r\n\r\nvi"))
        XCTAssertTrue(body.contains("filename=\"audio.wav\""))
    }

    func testUnauthenticatedEndpointSendsNoAuthorizationHeader() async throws {
        let transport = RemoteTransportSpy(status: 200, body: #"{"text":"hello"}"#)
        let subject = RemoteTranscriptionProvider(transport: transport)

        _ = try await subject.transcribe(
            audio: .init(samples: [0], sampleRate: 16_000),
            configuration: .init(baseURL: "http://localhost:8080/v1", model: " local-model ", language: ""),
            apiKey: nil
        )

        let capturedRequest = await transport.request
        let request = try XCTUnwrap(capturedRequest)
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
        XCTAssertTrue(String(decoding: try XCTUnwrap(request.httpBody), as: UTF8.self).contains("\r\n\r\nlocal-model\r\n"))
    }

    func testMultipartFieldsRejectEmptyModelAndLineBreakInjection() {
        let endpoint = URL(string: "https://host.example/audio/transcriptions")!
        for configuration in [
            RemoteProviderConfiguration(baseURL: "https://host.example", model: "  ", language: ""),
            RemoteProviderConfiguration(baseURL: "https://host.example", model: "\r\nmodel", language: ""),
            RemoteProviderConfiguration(baseURL: "https://host.example", model: "model\r\n--injected", language: ""),
            RemoteProviderConfiguration(baseURL: "https://host.example", model: "model", language: "vi\n--injected"),
            RemoteProviderConfiguration(baseURL: "https://host.example", model: "model", language: "vi\r\n")
        ] {
            XCTAssertThrowsError(try RemoteTranscriptionProvider.makeRequest(
                endpoint: endpoint,
                audio: .init(samples: [0], sampleRate: 16_000),
                configuration: configuration,
                apiKey: nil,
                boundary: "boundary"
            ), "Expected rejection for model=\(configuration.model.debugDescription), language=\(configuration.language.debugDescription)")
        }
    }

    func testAuthAndInvalidResponsesMapWithoutLeakingBody() async {
        for (status, body, expected) in [
            (401, "key=secret", "Remote authentication failed."),
            (200, "not-json", "The remote provider returned an invalid response.")
        ] {
            let subject = RemoteTranscriptionProvider(transport: RemoteTransportSpy(status: status, body: body))
            do {
                _ = try await subject.transcribe(
                    audio: .init(samples: [0], sampleRate: 16_000),
                    configuration: .init(baseURL: "https://host.example", model: "m", language: ""),
                    apiKey: "secret"
                )
                XCTFail("Expected failure")
            } catch let failure as DictationFailure {
                XCTAssertEqual(failure.message, expected)
                XCTAssertFalse(failure.message.contains("secret"))
            } catch { XCTFail("Unexpected error: \(error)") }
        }
    }
}

private enum TestFailure: Error { case expected }

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

private final class KeychainOperationsSpy: KeychainOperating {
    let updateStatus: OSStatus
    let addStatus: OSStatus
    private(set) var updateCallCount = 0
    private(set) var addCallCount = 0
    private(set) var deleteCallCount = 0

    init(updateStatus: OSStatus, addStatus: OSStatus) {
        self.updateStatus = updateStatus
        self.addStatus = addStatus
    }

    func copyMatching(_ query: CFDictionary, result: UnsafeMutablePointer<CFTypeRef?>?) -> OSStatus { errSecItemNotFound }
    func update(_ query: CFDictionary, attributes: CFDictionary) -> OSStatus {
        updateCallCount += 1
        return updateStatus
    }
    func add(_ attributes: CFDictionary) -> OSStatus {
        addCallCount += 1
        return addStatus
    }
    func delete(_ query: CFDictionary) -> OSStatus {
        deleteCallCount += 1
        return errSecSuccess
    }
}

private actor RemoteTransportSpy: RemoteTransport {
    let status: Int
    let body: String
    private(set) var request: URLRequest?

    init(status: Int, body: String) {
        self.status = status
        self.body = body
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        self.request = request
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
        return (Data(body.utf8), response)
    }

    func capturedRequest() -> URLRequest? { request }
}
