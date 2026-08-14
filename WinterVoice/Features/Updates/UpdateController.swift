import AppKit
import Foundation

enum UpdateCheckState: Equatable {
    case idle
    case checking
    case upToDate
    case available(AvailableUpdate)
    case downloading(AvailableUpdate, Double)
    case installing(AvailableUpdate)
    case installFailed(AvailableUpdate, String)
    case failed(String)

    /// The release an update banner or card should show, across the whole
    /// discovered → downloading → installing → failed lifecycle.
    var activeUpdate: AvailableUpdate? {
        switch self {
        case .available(let update), .downloading(let update, _),
             .installing(let update), .installFailed(let update, _):
            update
        case .idle, .checking, .upToDate, .failed:
            nil
        }
    }

    /// An install is underway; checks and further installs must not stomp it.
    var isInstallBusy: Bool {
        switch self {
        case .downloading, .installing: true
        default: false
        }
    }
}

/// Drives the "Updates" section in Settings: launch-time discovery of new
/// GitHub releases plus the manual Check for Updates action.
@MainActor
final class UpdateController: ObservableObject {
    @Published private(set) var state: UpdateCheckState = .idle

    private let checker: UpdateChecking
    private let installer: UpdateInstalling
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
        installer: UpdateInstalling? = nil,
        defaults: UserDefaults = .standard,
        openURL: ((URL) -> Void)? = nil,
        now: (() -> Date)? = nil
    ) {
        self.checker = checker ?? GitHubUpdateChecker()
        self.installer = installer ?? DMGUpdateInstaller()
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
        guard state != .checking, !state.isInstallBusy else { return }
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

    /// One-click update: download the release image in-process, verify it,
    /// swap the bundle in place, and relaunch. Falls back to the browser
    /// download when in-place install is impossible here (translocated or
    /// unwritable bundle, dev build, release without a .dmg asset).
    func install(_ update: AvailableUpdate) {
        guard !state.isInstallBusy else { return }
        guard update.downloadURL != nil, installer.installBlocker() == nil else {
            download(update)
            return
        }
        state = .downloading(update, 0)
        Task {
            do {
                try await installer.install(update) { [weak self] phase in
                    Task { @MainActor in self?.apply(phase, for: update) }
                }
                state = .installing(update)
                installer.relaunchAndTerminate()
            } catch {
                let message = (error as? UpdateInstallError)?.errorDescription
                    ?? error.localizedDescription
                state = .installFailed(update, message)
            }
        }
    }

    /// Phase callbacks hop to the main actor, so a stale download tick can
    /// land after the install advanced; it must not drag the state backwards.
    private func apply(_ phase: UpdateInstallPhase, for update: AvailableUpdate) {
        switch phase {
        case .downloading(let fraction):
            if case .downloading = state { state = .downloading(update, fraction) }
        case .installing:
            if state.isInstallBusy { state = .installing(update) }
        }
    }

    /// Browser fallback: hands the .dmg (or the release page) to the default
    /// browser, the pre-0.4 manual flow.
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
