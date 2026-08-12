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

struct OnboardingWizard: Equatable, Sendable {
    private(set) var pageIndex = 0

    var currentPermission: AppPermission { AppPermission.allCases[pageIndex] }
    var canGoBack: Bool { pageIndex > 0 }
    var isLastPage: Bool { pageIndex == AppPermission.allCases.count - 1 }

    mutating func back() { pageIndex = max(0, pageIndex - 1) }
    mutating func next() { pageIndex = min(AppPermission.allCases.count - 1, pageIndex + 1) }
    mutating func reset() { pageIndex = 0 }
}
