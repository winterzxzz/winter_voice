import Foundation

enum HotkeyHealth: Equatable, Sendable {
    case permissionRequired
    case listening
    case installationFailed

    var title: String {
        switch self {
        case .permissionRequired: "Input Monitoring required"
        case .listening: "Listening for Right Option"
        case .installationFailed: "Hotkey unavailable"
        }
    }

    var detail: String {
        switch self {
        case .permissionRequired:
            "Allow WinterVoice in Privacy & Security → Input Monitoring, then return to WinterVoice."
        case .listening:
            "Hold Right Option to record and release it to transcribe."
        case .installationFailed:
            "WinterVoice could not install or recover its global hotkey listener. Return to the app to retry."
        }
    }
}
