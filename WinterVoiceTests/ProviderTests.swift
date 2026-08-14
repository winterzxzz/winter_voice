import Foundation
import AVFoundation
import CryptoKit
import Security
import XCTest
@testable import WinterVoice

@MainActor
final class ProviderConfigurationTests: XCTestCase {
    func testSelectedLocalModelIsReadyAndTranscribesThroughLocalRuntime() async throws {
        let suite = "LocalRuntimeMessageTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let source = root.appendingPathComponent("model.bin")
        let bytes = Data("local model".utf8)
        try bytes.write(to: source)
        let hash = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
        let descriptor = ModelDescriptor(
            id: "local-test", displayName: "Local Test", family: "whisper",
            runtime: "whisper.cpp", variant: "tiny", quantization: nil,
            downloadURL: URL(string: "https://models.example/model.bin")!,
            fileName: "model.bin", fileSize: Int64(bytes.count), sha256: hash
        )
        let models = ModelManager(root: root.appendingPathComponent("store"))
        try await models.installDownloadedFile(source, descriptor: descriptor)
        await models.select(descriptor.id)
        XCTAssertNil(models.lastError)
        let store = ProviderConfigurationStore(defaults: defaults, credentials: CredentialStoreSpy())
        store.mode = .local
        let runtime = LocalRuntimeSpy(result: "xin chào")
        let subject = ConfiguredTranscriber(
            recorder: AudioRecorderSpy(samples: [0.1, -0.1]),
            configuration: store,
            models: models,
            localRuntime: runtime
        )

        XCTAssertNoThrow(try subject.validateConfiguration())
        try await subject.start()
        let transcription = try await subject.stop()
        XCTAssertEqual(transcription, "xin chào")
        let request = await runtime.request
        XCTAssertEqual(request?.audio.samples, [0.1, -0.1])
        XCTAssertEqual(request?.audio.sampleRate, 16_000)
        XCTAssertEqual(request?.modelURL.lastPathComponent, "model.bin")
        XCTAssertNil(request?.language)
    }

    func testEnglishOnlyModelRoutesEnglishLanguageToLocalRuntime() async throws {
        let suite = "EnglishOnlyRoutingTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let source = root.appendingPathComponent("ggml-tiny.en.bin")
        let bytes = Data("english-only model".utf8)
        try bytes.write(to: source)
        let hash = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
        let descriptor = ModelDescriptor(
            id: "local-test-en", displayName: "Local Test English", family: "whisper",
            runtime: "whisper.cpp", variant: "tiny.en", quantization: nil,
            downloadURL: URL(string: "https://models.example/ggml-tiny.en.bin")!,
            fileName: "ggml-tiny.en.bin", fileSize: Int64(bytes.count), sha256: hash
        )
        let models = ModelManager(root: root.appendingPathComponent("store"))
        try await models.installDownloadedFile(source, descriptor: descriptor)
        await models.select(descriptor.id)
        XCTAssertNil(models.lastError)
        XCTAssertEqual(models.activeModel?.isEnglishOnly, true)
        let store = ProviderConfigurationStore(defaults: defaults, credentials: CredentialStoreSpy())
        store.mode = .local
        // Even an explicit selection must not override an English-only model.
        store.languageCode = "vi"
        let runtime = LocalRuntimeSpy(result: "hello")
        let subject = ConfiguredTranscriber(
            recorder: AudioRecorderSpy(samples: [0.1, -0.1]),
            configuration: store,
            models: models,
            localRuntime: runtime
        )

        try await subject.start()
        let transcription = try await subject.stop()
        XCTAssertEqual(transcription, "hello")
        let request = await runtime.request
        XCTAssertEqual(request?.modelURL.lastPathComponent, "ggml-tiny.en.bin")
        XCTAssertEqual(request?.language, "en")
    }

    func testSelectedLanguageRoutesToLocalRuntimeForMultilingualModel() async throws {
        let suite = "SelectedLanguageRoutingTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let source = root.appendingPathComponent("model.bin")
        let bytes = Data("multilingual model".utf8)
        try bytes.write(to: source)
        let hash = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
        let descriptor = ModelDescriptor(
            id: "local-test-multi", displayName: "Local Test Multi", family: "whisper",
            runtime: "whisper.cpp", variant: "tiny", quantization: nil,
            downloadURL: URL(string: "https://models.example/model.bin")!,
            fileName: "model.bin", fileSize: Int64(bytes.count), sha256: hash
        )
        let models = ModelManager(root: root.appendingPathComponent("store"))
        try await models.installDownloadedFile(source, descriptor: descriptor)
        await models.select(descriptor.id)
        let store = ProviderConfigurationStore(defaults: defaults, credentials: CredentialStoreSpy())
        store.mode = .local
        store.languageCode = "vi"
        let runtime = LocalRuntimeSpy(result: "xin chào")
        let subject = ConfiguredTranscriber(
            recorder: AudioRecorderSpy(samples: [0.1, -0.1]),
            configuration: store,
            models: models,
            localRuntime: runtime
        )

        try await subject.start()
        _ = try await subject.stop()
        let request = await runtime.request
        XCTAssertEqual(request?.language, "vi")
    }

    func testLanguageSelectionPersistsAndAdoptsLegacyRemoteLanguage() throws {
        let suite = "LanguagePersistenceTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = ProviderConfigurationStore(defaults: defaults, credentials: CredentialStoreSpy())
        XCTAssertNil(store.languageCode, "A fresh install defaults to auto-detect")
        store.languageCode = "vi"
        XCTAssertEqual(
            ProviderConfigurationStore(defaults: defaults, credentials: CredentialStoreSpy()).languageCode,
            "vi"
        )
        store.languageCode = nil
        XCTAssertNil(
            ProviderConfigurationStore(defaults: defaults, credentials: CredentialStoreSpy()).languageCode,
            "Returning to auto-detect must persist, not fall back to the legacy value"
        )

        // Pre-picker installs stored a free-text code inside the remote JSON;
        // a known code is adopted once, junk is dropped.
        for (legacy, expected) in [("VI ", "vi"), ("Vietnamese please", nil)] {
            let legacySuite = "\(suite).\(expected ?? "junk")"
            let legacyDefaults = try XCTUnwrap(UserDefaults(suiteName: legacySuite))
            defer { legacyDefaults.removePersistentDomain(forName: legacySuite) }
            let json = #"{"baseURL":"https://host.example/v1","model":"m","language":"\#(legacy)"}"#
            legacyDefaults.set(Data(json.utf8), forKey: "transcription.remote.configuration")
            let migrated = ProviderConfigurationStore(defaults: legacyDefaults, credentials: CredentialStoreSpy())
            XCTAssertEqual(migrated.languageCode, expected)
            XCTAssertEqual(migrated.remote.model, "m", "Migration must not disturb the remote configuration")
        }
    }

    func testModeRemoteConfigurationAndCredentialPersistAtTheirOwnedStores() throws {
        let suite = "ProviderConfigurationTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let credentials = CredentialStoreSpy()
        let subject = ProviderConfigurationStore(defaults: defaults, credentials: credentials)

        subject.mode = .remote
        try subject.saveRemote(
            .init(baseURL: "https://host.example/v1", model: "transcriber"),
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
        try store.saveRemote(.init(baseURL: "https://host.example/v1", model: "m"), apiKey: nil)
        XCTAssertTrue(store.status(localModels: models).isReady)
        XCTAssertTrue(store.status(localModels: models).readiness.detail.contains("without authentication"))
        try store.saveRemote(.init(baseURL: "https://host.example/v1", model: "m"), apiKey: "secret")
        let remote = store.status(localModels: models)
        XCTAssertTrue(remote.isReady)
        XCTAssertTrue(remote.overviewSummary.contains("Transcription is ready"))
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
        try store.saveRemote(.init(baseURL: "https://host.example/v1", model: "m"), apiKey: "secret")

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
            language: nil,
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
        try store.saveRemote(.init(baseURL: "https://host.example", model: "m"), apiKey: nil)

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
            try RemoteTranscriptionProvider.endpoint(for: .init(baseURL: "https://host.example/v1", model: "m")).path,
            "/v1/audio/transcriptions"
        )
        XCTAssertNoThrow(try RemoteTranscriptionProvider.endpoint(for: .init(baseURL: "http://192.168.1.4:9000/v1", model: "m")))
        XCTAssertThrowsError(try RemoteTranscriptionProvider.endpoint(for: .init(baseURL: "http://public.example/v1", model: "m")))
        XCTAssertThrowsError(try RemoteTranscriptionProvider.endpoint(for: .init(baseURL: "https://user:password@host.example/v1", model: "m")))
        XCTAssertThrowsError(try RemoteTranscriptionProvider.endpoint(for: .init(baseURL: "https://host.example/v1#secret", model: "m")))
        let queryEndpoint = try RemoteTranscriptionProvider.endpoint(for: .init(baseURL: "https://host.example/v1?deployment=a", model: "m"))
        XCTAssertEqual(queryEndpoint.query, "deployment=a", "Non-secret endpoint query parameters are deliberately preserved")
    }

    func testIsLocalOrLANRequiresHostToBeAnIPLiteralOrLocalName() {
        for host in ["localhost", "myhost.local", "127.0.0.1", "10.0.0.5", "192.168.1.4", "172.16.0.1", "::1", "[::1]"] {
            XCTAssertTrue(RemoteTranscriptionProvider.isLocalOrLAN(host), "Expected \(host) to count as local/LAN")
        }
        for host in ["10.1.2.3.attacker.com", "8.8.8.8", "172.32.0.1", "public.example"] {
            XCTAssertFalse(RemoteTranscriptionProvider.isLocalOrLAN(host), "Expected \(host) to be rejected")
        }
        XCTAssertThrowsError(
            try RemoteTranscriptionProvider.endpoint(for: .init(baseURL: "http://10.1.2.3.attacker.com/v1", model: "m")),
            "A public DNS name embedding a private IP must not unlock plain HTTP"
        )
        XCTAssertNoThrow(try RemoteTranscriptionProvider.endpoint(for: .init(baseURL: "http://[::1]:8080/v1", model: "m")))
    }

    func testMultipartRequestAndStandardTextResponse() async throws {
        let transport = RemoteTransportSpy(status: 200, body: #"{"text":"hello"}"#)
        let subject = RemoteTranscriptionProvider(transport: transport)
        let configuration = RemoteProviderConfiguration(baseURL: "https://host.example/v1", model: "model-a")

        let text = try await subject.transcribe(
            audio: .init(samples: [0, 0.5], sampleRate: 16_000),
            configuration: configuration,
            language: "vi",
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
            configuration: .init(baseURL: "http://localhost:8080/v1", model: " local-model "),
            language: nil,
            apiKey: nil
        )

        let capturedRequest = await transport.request
        let request = try XCTUnwrap(capturedRequest)
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
        let body = String(decoding: try XCTUnwrap(request.httpBody), as: UTF8.self)
        XCTAssertTrue(body.contains("\r\n\r\nlocal-model\r\n"))
        XCTAssertFalse(body.contains("name=\"language\""), "Auto-detect must omit the language field entirely")
    }

    func testMultipartFieldsRejectEmptyModelAndLineBreakInjection() {
        let endpoint = URL(string: "https://host.example/audio/transcriptions")!
        for configuration in [
            RemoteProviderConfiguration(baseURL: "https://host.example", model: "  "),
            RemoteProviderConfiguration(baseURL: "https://host.example", model: "\r\nmodel"),
            RemoteProviderConfiguration(baseURL: "https://host.example", model: "model\r\n--injected")
        ] {
            XCTAssertThrowsError(try RemoteTranscriptionProvider.makeRequest(
                endpoint: endpoint,
                audio: .init(samples: [0], sampleRate: 16_000),
                configuration: configuration,
                language: nil,
                apiKey: nil,
                boundary: "boundary"
            ), "Expected rejection for model=\(configuration.model.debugDescription)")
        }
    }

    func testUnknownLanguageCodeIsDroppedFromMultipartBody() throws {
        let request = try RemoteTranscriptionProvider.makeRequest(
            endpoint: URL(string: "https://host.example/audio/transcriptions")!,
            audio: .init(samples: [0], sampleRate: 16_000),
            configuration: .init(baseURL: "https://host.example", model: "model"),
            language: "vi\r\n--injected",
            apiKey: nil,
            boundary: "boundary"
        )
        let body = String(decoding: try XCTUnwrap(request.httpBody), as: UTF8.self)
        XCTAssertFalse(body.contains("name=\"language\""), "Codes outside the picker list must never reach the body")
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
                    configuration: .init(baseURL: "https://host.example", model: "m"),
                    language: nil,
                    apiKey: "secret"
                )
                XCTFail("Expected failure")
            } catch let failure as DictationFailure {
                XCTAssertEqual(failure.message, expected)
                XCTAssertFalse(failure.message.contains("secret"))
            } catch { XCTFail("Unexpected error: \(error)") }
        }
    }

    func testConnectionProbeAcceptsEmptyTranscriptionAndSendsRealAudioPayload() async throws {
        let transport = RemoteTransportSpy(status: 200, body: #"{"text":""}"#)
        let subject = RemoteTranscriptionProvider(transport: transport)

        try await subject.testConnection(
            configuration: .init(baseURL: "https://host.example/v1", model: "m"),
            apiKey: "probe-key"
        )

        XCTAssertEqual(RemoteTranscriptionProvider.connectionProbeAudio.samples.count, 3_200)
        XCTAssertEqual(RemoteTranscriptionProvider.connectionProbeAudio.sampleRate, 16_000)
        let capturedRequest = await transport.request
        let request = try XCTUnwrap(capturedRequest)
        XCTAssertEqual(request.url?.path, "/v1/audio/transcriptions")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer probe-key")
        let body = try XCTUnwrap(request.httpBody)
        XCTAssertNotNil(body.range(of: Data("filename=\"audio.wav\"".utf8)))
        XCTAssertGreaterThan(body.count, 12_800, "The probe carries 0.2 s of 16 kHz audio (3,200 four-byte samples)")
    }

    func testConnectionProbeMapsAuthenticationFailureLikeTranscription() async {
        let subject = RemoteTranscriptionProvider(transport: RemoteTransportSpy(status: 401, body: "key=secret"))
        do {
            try await subject.testConnection(
                configuration: .init(baseURL: "https://host.example/v1", model: "m"),
                apiKey: "secret"
            )
            XCTFail("Expected failure")
        } catch let failure as DictationFailure {
            XCTAssertEqual(failure.message, "Remote authentication failed.")
            XCTAssertFalse(failure.message.contains("secret"))
        } catch { XCTFail("Unexpected error: \(error)") }
    }

    func testConnectionProbeWithoutKeySendsNoAuthorizationHeader() async throws {
        let transport = RemoteTransportSpy(status: 200, body: #"{"text":"ok"}"#)

        try await RemoteTranscriptionProvider(transport: transport).testConnection(
            configuration: .init(baseURL: "http://localhost:8080/v1", model: "m"),
            apiKey: nil
        )

        let capturedRequest = await transport.request
        let request = try XCTUnwrap(capturedRequest)
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
    }
}

final class WhisperContextActorGuardTests: XCTestCase {
    func testRejectsAudioThatIsNot16kHzBeforeAnyModelWork() async {
        await assertTranscriptionFails(
            audio: RecordedAudio(samples: [0.1, -0.1], sampleRate: 44_100),
            messageContaining: "unsupported audio"
        )
    }

    func testRejectsEmptyRecordingBeforeAnyModelWork() async {
        await assertTranscriptionFails(
            audio: RecordedAudio(samples: [], sampleRate: 16_000),
            messageContaining: "No speech was recorded"
        )
    }

    func testRejectsMissingModelFileBeforeLoadingRuntime() async {
        await assertTranscriptionFails(
            audio: RecordedAudio(samples: [0.1, -0.1], sampleRate: 16_000),
            modelURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("WhisperGuardTests.\(UUID().uuidString)")
                .appendingPathComponent("ggml-missing.bin"),
            messageContaining: "missing"
        )
    }

    private func assertTranscriptionFails(
        audio: RecordedAudio,
        modelURL: URL = URL(fileURLWithPath: "/nonexistent/whisper-guard-model.bin"),
        messageContaining fragment: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        do {
            _ = try await WhisperContextActor().transcribe(audio, modelURL: modelURL, language: nil)
            XCTFail("Expected transcription to be rejected", file: file, line: line)
        } catch let failure as DictationFailure {
            XCTAssertTrue(
                failure.message.contains(fragment),
                "\(failure.message.debugDescription) should contain \(fragment.debugDescription)",
                file: file, line: line
            )
        } catch {
            XCTFail("Unexpected error: \(error)", file: file, line: line)
        }
    }
}

final class WhisperRuntimeIntegrationTests: XCTestCase {
    func testRealWhisperRuntimeTranscribesFixtureWhenPathsAreProvided() async throws {
        let environment = ProcessInfo.processInfo.environment
        let modelPath = environment["WINTERVOICE_WHISPER_TEST_MODEL"]
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("WinterVoice/Models/whisper-tiny/ggml-tiny.bin").path
        let audioPath = environment["WINTERVOICE_WHISPER_TEST_AUDIO"] ?? "/tmp/whisper-jfk.wav"
        guard FileManager.default.fileExists(atPath: modelPath),
              FileManager.default.fileExists(atPath: audioPath) else {
            throw XCTSkip("Install Whisper Tiny and provide the JFK fixture to run this integration test.")
        }
        let file = try AVAudioFile(forReading: URL(fileURLWithPath: audioPath))
        let format = file.processingFormat
        XCTAssertEqual(format.sampleRate, 16_000)
        XCTAssertEqual(format.channelCount, 1)
        let buffer = try XCTUnwrap(
            AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(file.length))
        )
        try file.read(into: buffer)
        let channel = try XCTUnwrap(buffer.floatChannelData?[0])
        let samples = Array(UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength)))

        let transcription = try await WhisperContextActor().transcribe(
            RecordedAudio(samples: samples, sampleRate: format.sampleRate),
            modelURL: URL(fileURLWithPath: modelPath),
            language: "en"
        )

        XCTAssertTrue(transcription.localizedCaseInsensitiveContains("fellow Americans"))
    }
}

private enum TestFailure: Error { case expected }

@MainActor
private final class AudioRecorderSpy: AudioRecording {
    private let samples: [Float]
    init(samples: [Float] = []) { self.samples = samples }
    func start() throws {}
    func stop() throws -> RecordedAudio { RecordedAudio(samples: samples, sampleRate: 16_000) }
    func cancel() {}
}

private actor LocalRuntimeSpy: LocalTranscriptionRunning {
    struct Request: Sendable {
        let audio: RecordedAudio
        let modelURL: URL
        let language: String?
    }

    private(set) var request: Request?
    private let result: String

    init(result: String) { self.result = result }

    func transcribe(_ audio: RecordedAudio, modelURL: URL, language: String?) -> String {
        request = Request(audio: audio, modelURL: modelURL, language: language)
        return result
    }

    nonisolated func cancelActiveTranscription() {}
    func unloadContext() {}
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
