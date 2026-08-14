import Foundation

protocol OnboardingCompletionStoring: AnyObject {
    var isComplete: Bool { get set }
}

final class UserDefaultsOnboardingCompletionStore: OnboardingCompletionStoring {
    private let defaults: UserDefaults
    private let key: String

    init(
        defaults: UserDefaults = .standard,
        key: String = "onboarding.permissions.complete"
    ) {
        self.defaults = defaults
        self.key = key
    }

    var isComplete: Bool {
        get { defaults.bool(forKey: key) }
        set { defaults.set(newValue, forKey: key) }
    }
}

final class OnboardingInteractor {
    private let completionStore: OnboardingCompletionStoring

    init(completionStore: OnboardingCompletionStoring) {
        self.completionStore = completionStore
    }

    /// Setup presents until it has been completed once — and again whenever
    /// required permissions are missing at launch, so a copy whose grants
    /// were revoked (update, new signature, Settings change) reopens the
    /// guide instead of booting into a shell that cannot dictate.
    func shouldPresentOnLaunch(permissions: PermissionSnapshot) -> Bool {
        !completionStore.isComplete || OnboardingProgress(permissions: permissions) != .ready
    }

    func complete(with permissions: PermissionSnapshot) -> Bool {
        guard OnboardingProgress(permissions: permissions) == .ready else {
            return false
        }
        completionStore.isComplete = true
        return true
    }

    func deferForNow() {
        // Deferral is intentionally session-only; it must never become completion.
    }

    func resetCompletion() {
        completionStore.isComplete = false
    }
}
