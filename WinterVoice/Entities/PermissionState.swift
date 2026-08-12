import Foundation

enum AppPermission: CaseIterable, Identifiable, Sendable {
    case microphone
    case inputMonitoring
    case accessibility

    var id: Self { self }
    var title: String {
        switch self {
        case .microphone: "Microphone"
        case .inputMonitoring: "Input Monitoring"
        case .accessibility: "Accessibility"
        }
    }
    var explanation: String {
        switch self {
        case .microphone: "Captures audio while Right Option is held."
        case .inputMonitoring: "Observes the global Right Option hotkey without changing keyboard input."
        case .accessibility: "Captures the focused field and inserts text back into the focused app safely."
        }
    }
}

enum PermissionStatus: String, Sendable {
    case notDetermined = "Not requested"
    case authorized = "Allowed"
    case denied = "Denied"
    case restricted = "Restricted"
}

enum PermissionRequestState: Equatable, Sendable {
    case idle
    case requesting(AppPermission)
    case completed(AppPermission, PermissionStatus)
}

struct PermissionSnapshot: Equatable, Sendable {
    var microphone: PermissionStatus
    var inputMonitoring: PermissionStatus
    var accessibility: PermissionStatus

    subscript(_ permission: AppPermission) -> PermissionStatus {
        switch permission {
        case .microphone: microphone
        case .inputMonitoring: inputMonitoring
        case .accessibility: accessibility
        }
    }
}
