import Foundation

enum FeatureAvailability: Equatable, Sendable {
    case available
    case planned
}

enum AppShellDestination: String, CaseIterable, Identifiable, Sendable {
    case overview
    case history
    case dictionary
    case hotkey
    case settings

    var id: Self { self }

    var availability: FeatureAvailability {
        switch self {
        case .overview, .history, .dictionary, .hotkey, .settings:
            .available
        }
    }
}
