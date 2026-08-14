import AppKit
import Foundation

enum UpdateCheckState: Equatable {
    case idle
    case checking
    case upToDate
    case available(AvailableUpdate)
    case failed(String)
}

/// Drives the "Updates" section in Settings: launch-time discovery of new
/// GitHub releases plus the manual Check for Updates action.
@MainActor
final class UpdateController: ObservableObject {
    @Published private(set) var state: UpdateCheckState = .idle

    private let checker: UpdateChecking
    private let defaults: UserDefaults
    private let openURL: (URL) -> Void
    private let now: () -> Date
    private var hasAutoCheckedThisLaunch = false

    private static let lastAutoCheckKey = "WVUpdateLastAutoCheck"
    private static let skippedVersionKey = "WVUpdateSkippedVersion"
    private static let autoCheckInterval: TimeInterval = 60 * 60 * 24

    var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    }

    init(
        checker: UpdateChecking? = nil,
        defaults: UserDefaults = .standard,
        openURL: ((URL) -> Void)? = nil,
        now: (() -> Date)? = nil
    ) {
        self.checker = checker ?? GitHubUpdateChecker()
        self.defaults = defaults
        self.openURL = openURL ?? { NSWorkspace.shared.open($0) }
        self.now = now ?? Date.init
    }

    /// Launch-time check: at most once per app launch and once per day, and a
    /// release the user chose to skip stays silent. Failures stay silent too —
    /// an offline launch must not surface an update error the user never
    /// asked about.
    func checkAutomatically() {
        guard !hasAutoCheckedThisLaunch else { return }
        hasAutoCheckedThisLaunch = true
        let lastCheck = defaults.object(forKey: Self.lastAutoCheckKey) as? Date
        if let lastCheck, now().timeIntervalSince(lastCheck) < Self.autoCheckInterval { return }
        Task {
            defaults.set(now(), forKey: Self.lastAutoCheckKey)
            guard let update = try? await checker.fetchAvailableUpdate() else { return }
            guard update.version != defaults.string(forKey: Self.skippedVersionKey) else { return }
            state = .available(update)
        }
    }

    /// Manual check from Settings: always reports, and clears any skip so the
    /// user sees the release they explicitly asked about.
    func checkNow() {
        guard state != .checking else { return }
        state = .checking
        defaults.removeObject(forKey: Self.skippedVersionKey)
        Task {
            do {
                defaults.set(now(), forKey: Self.lastAutoCheckKey)
                if let update = try await checker.fetchAvailableUpdate() {
                    state = .available(update)
                } else {
                    state = .upToDate
                }
            } catch {
                state = .failed("Could not reach GitHub. Check your connection and try again.")
            }
        }
    }

    func download(_ update: AvailableUpdate) {
        openURL(update.downloadURL ?? update.releaseURL)
    }

    func viewRelease(_ update: AvailableUpdate) {
        openURL(update.releaseURL)
    }

    /// Hide this release from future automatic checks; the next manual check
    /// or the next published version surfaces the section again.
    func skip(_ update: AvailableUpdate) {
        defaults.set(update.version, forKey: Self.skippedVersionKey)
        state = .idle
    }
}
