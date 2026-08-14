import Foundation

@MainActor
protocol RemoteConnectionTesting: AnyObject {
    func test(configuration: RemoteProviderConfiguration, apiKey: String?) async throws
}

@MainActor
final class RemoteConnectionTester: RemoteConnectionTesting {
    private let provider: RemoteTranscriptionProvider

    init(provider: RemoteTranscriptionProvider = .init()) {
        self.provider = provider
    }

    func test(configuration: RemoteProviderConfiguration, apiKey: String?) async throws {
        try await provider.testConnection(configuration: configuration, apiKey: apiKey)
    }
}

/// Owns the Transcription page's remote-configuration flow so the view only
/// renders state and emits actions; HTTP, Keychain, and persistence never run
/// in view code.
@MainActor
final class TranscriptionSettingsController: ObservableObject {
    @Published var baseURL = ""
    @Published var remoteModel = ""
    @Published var apiKey = ""
    @Published private(set) var remoteResult: String?

    private let configuration: ProviderConfigurationStore
    private let connectionTester: RemoteConnectionTesting
    private var testTask: Task<Void, Never>?

    init(
        configuration: ProviderConfigurationStore,
        connectionTester: RemoteConnectionTesting? = nil
    ) {
        self.configuration = configuration
        self.connectionTester = connectionTester ?? RemoteConnectionTester()
    }

    var draft: RemoteProviderConfiguration {
        .init(baseURL: baseURL, model: remoteModel)
    }

    func loadRemoteDraft() {
        baseURL = configuration.remote.baseURL
        remoteModel = configuration.remote.model
    }

    func saveRemote() {
        do {
            _ = try RemoteTranscriptionProvider.endpoint(for: draft)
            try configuration.saveRemote(draft, apiKey: apiKey.isEmpty ? nil : apiKey)
            apiKey = ""
            remoteResult = "Configuration saved."
        } catch let failure as DictationFailure {
            remoteResult = failure.message
        } catch {
            remoteResult = "Could not save the configuration."
        }
    }

    /// Tests the DRAFT configuration. Testing must never persist the draft or
    /// write the typed key to Keychain — only Save Configuration commits.
    func testRemoteConnection() {
        let draft = draft
        do {
            _ = try RemoteTranscriptionProvider.endpoint(for: draft)
        } catch let failure as DictationFailure {
            remoteResult = failure.message
            return
        } catch {
            remoteResult = "Configuration is invalid."
            return
        }
        remoteResult = "Testing connection…"
        let typedKey = apiKey
        testTask?.cancel()
        testTask = Task { [weak self] in
            guard let self else { return }
            let key: String?
            if typedKey.isEmpty {
                do {
                    key = try self.configuration.apiKey()
                } catch let failure as DictationFailure {
                    self.remoteResult = failure.message
                    return
                } catch {
                    self.remoteResult = "Could not read the API key."
                    return
                }
            } else {
                key = typedKey
            }
            do {
                try await self.connectionTester.test(configuration: draft, apiKey: key)
                guard !Task.isCancelled else { return }
                self.remoteResult = "Connected successfully. Use Save Configuration to keep these settings."
            } catch let failure as DictationFailure {
                guard !Task.isCancelled else { return }
                self.remoteResult = failure.message
            } catch {
                guard !Task.isCancelled else { return }
                self.remoteResult = "Connection test failed."
            }
        }
    }

    func removeAPIKey() {
        do {
            try configuration.removeAPIKey()
            apiKey = ""
            remoteResult = "API key removed. Remote requests will use no authentication."
        } catch let failure as DictationFailure {
            remoteResult = failure.message
        } catch {
            remoteResult = "Could not remove the API key."
        }
    }
}
