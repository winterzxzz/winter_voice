import Foundation

enum AppPermission: CaseIterable, Identifiable, Sendable {
    case microphone
    case speechRecognition
    case inputMonitoring
    case accessibility

    var id: Self { self }
    var title: String {
        switch self {
        case .microphone: "Microphone"
        case .speechRecognition: "Speech Recognition"
        case .inputMonitoring: "Input Monitoring"
        case .accessibility: "Accessibility"
        }
    }
    var explanation: String {
        switch self {
        case .microphone: "Records your voice while Right Option is held."
        case .speechRecognition: "Converts audio to text on this Mac."
        case .inputMonitoring: "Observes the global Right Option hotkey without changing keyboard input."
        case .accessibility: "Captures the original focused field and inserts text back into it safely."
        }
    }
}

enum PermissionStatus: String, Sendable {
    case notDetermined = "Not requested"
    case authorized = "Allowed"
    case denied = "Denied"
    case restricted = "Restricted"
}

struct PermissionSnapshot: Equatable, Sendable {
    var microphone: PermissionStatus
    var speechRecognition: PermissionStatus
    var inputMonitoring: PermissionStatus
    var accessibility: PermissionStatus

    subscript(_ permission: AppPermission) -> PermissionStatus {
        switch permission {
        case .microphone: microphone
        case .speechRecognition: speechRecognition
        case .inputMonitoring: inputMonitoring
        case .accessibility: accessibility
        }
    }
}
