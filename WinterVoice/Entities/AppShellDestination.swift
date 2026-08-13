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
    case history
    case dictionary

    var id: Self { self }

    var availability: FeatureAvailability {
        switch self {
        case .overview, .permissions, .transcription, .hotkey, .privacy, .history, .dictionary:
            .available
        }
    }
}
