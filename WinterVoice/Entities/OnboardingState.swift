import Foundation

enum OnboardingProgress: Equatable, Sendable {
    case needsPermission(AppPermission)
    case ready

    init(permissions: PermissionSnapshot) {
        if let permission = AppPermission.allCases.first(where: {
            permissions[$0] != .authorized
        }) {
            self = .needsPermission(permission)
        } else {
            self = .ready
        }
    }
}
