import Foundation

enum FeatureAvailability: Equatable, Sendable {
    case available
    case planned
}

enum AppShellDestination: String, CaseIterable, Identifiable, Sendable {
    case overview
    case permissions
    case transcription
    case hotkey
    case privacy
    case models
    case remoteProviders
    case history
    case dictionary

    var id: Self { self }

    var availability: FeatureAvailability {
        switch self {
        case .overview, .permissions, .transcription, .hotkey, .privacy:
            .available
        case .models, .remoteProviders, .history, .dictionary:
            .planned
        }
    }
}

struct TranscriptionCapability: Equatable, Sendable {
    let providerName: String
    let modeName: String
    let localeIdentifier: String
    let localeDisplayName: String
    let isRecognizerAvailable: Bool
    let supportsOnDeviceRecognition: Bool
}
