import Combine
import Foundation
import Security

protocol CredentialStoring: AnyObject {
    func read() throws -> String?
    func write(_ value: String) throws
    func delete() throws
}

protocol KeychainOperating: AnyObject {
    func copyMatching(_ query: CFDictionary, result: UnsafeMutablePointer<CFTypeRef?>?) -> OSStatus
    func update(_ query: CFDictionary, attributes: CFDictionary) -> OSStatus
    func add(_ attributes: CFDictionary) -> OSStatus
    func delete(_ query: CFDictionary) -> OSStatus
}

final class SystemKeychainOperations: KeychainOperating {
    func copyMatching(_ query: CFDictionary, result: UnsafeMutablePointer<CFTypeRef?>?) -> OSStatus {
        SecItemCopyMatching(query, result)
    }
    func update(_ query: CFDictionary, attributes: CFDictionary) -> OSStatus {
        SecItemUpdate(query, attributes)
    }
    func add(_ attributes: CFDictionary) -> OSStatus { SecItemAdd(attributes, nil) }
    func delete(_ query: CFDictionary) -> OSStatus { SecItemDelete(query) }
}

final class KeychainCredentialStore: CredentialStoring {
    private let service = "com.winterzxzz.WinterVoice.remote-provider"
    private let account = "api-key"
    private let operations: KeychainOperating

    init(operations: KeychainOperating = SystemKeychainOperations()) {
        self.operations = operations
    }

    func read() throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = operations.copyMatching(query as CFDictionary, result: &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = item as? Data else {
            throw DictationFailure(message: "Could not read the API key.", recovery: "Check Keychain access and try again.")
        }
        return String(data: data, encoding: .utf8)
    }

    func write(_ value: String) throws {
        let identity: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let valueAttributes: [String: Any] = [
            kSecValueData as String: Data(value.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        let updateStatus = operations.update(identity as CFDictionary, attributes: valueAttributes as CFDictionary)
        if updateStatus == errSecSuccess { return }
        guard updateStatus == errSecItemNotFound else {
            throw DictationFailure(message: "Could not save the API key.", recovery: "Check Keychain access and try again.")
        }
        var newItem = identity
        newItem.merge(valueAttributes) { _, new in new }
        guard operations.add(newItem as CFDictionary) == errSecSuccess else {
            throw DictationFailure(message: "Could not save the API key.", recovery: "Check Keychain access and try again.")
        }
    }

    func delete() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let status = operations.delete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw DictationFailure(message: "Could not remove the API key.", recovery: "Check Keychain access and try again.")
        }
    }
}

@MainActor
final class ProviderConfigurationStore: ObservableObject {
    @Published var mode: ProviderMode {
        didSet { defaults.set(mode.rawValue, forKey: Keys.mode) }
    }
    @Published var remote: RemoteProviderConfiguration
    @Published private(set) var hasAPIKey: Bool

    private enum Keys {
        static let mode = "transcription.provider.mode"
        static let remote = "transcription.remote.configuration"
    }
    private let defaults: UserDefaults
    private let credentials: CredentialStoring

    init(defaults: UserDefaults = .standard, credentials: CredentialStoring = KeychainCredentialStore()) {
        self.defaults = defaults
        self.credentials = credentials
        mode = defaults.string(forKey: Keys.mode).flatMap(ProviderMode.init(rawValue:)) ?? .local
        remote = defaults.data(forKey: Keys.remote).flatMap { try? JSONDecoder().decode(RemoteProviderConfiguration.self, from: $0) } ?? .init()
        hasAPIKey = ((try? credentials.read()) ?? nil)?.isEmpty == false
    }

    func saveRemote(_ configuration: RemoteProviderConfiguration, apiKey: String?) throws {
        remote = configuration
        defaults.set(try JSONEncoder().encode(configuration), forKey: Keys.remote)
        if let apiKey, !apiKey.isEmpty { try credentials.write(apiKey) }
        hasAPIKey = (try credentials.read())?.isEmpty == false
    }

    func apiKey() throws -> String? { try credentials.read() }

    func removeAPIKey() throws {
        try credentials.delete()
        hasAPIKey = false
    }

    func readiness(localModels: ModelManager) -> ProviderReadiness {
        switch mode {
        case .local:
            guard let active = localModels.activeModel else {
                return .unavailable("No active local model. No supported downloadable model is published yet.")
            }
            return .unavailable("\(active.displayName) is installed, but the approved whisper.cpp runtime dependency is not present.")
        case .remote:
            do {
                _ = try RemoteTranscriptionProvider.endpoint(for: remote)
                return .ready(hasAPIKey
                    ? "Generic OpenAI-compatible remote provider is configured with Keychain authentication."
                    : "Generic OpenAI-compatible remote provider is configured without authentication.")
            } catch let error as DictationFailure {
                return .unavailable(error.message)
            } catch {
                return .unavailable("Remote configuration is invalid.")
            }
        }
    }

    func status(localModels: ModelManager) -> ProviderStatus {
        ProviderStatus(mode: mode, readiness: readiness(localModels: localModels))
    }
}
