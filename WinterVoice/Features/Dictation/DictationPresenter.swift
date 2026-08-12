import AppKit
import Combine

@MainActor
final class DictationPresenter: ObservableObject {
    @Published private(set) var state: DictationState = .idle
    @Published private(set) var permissions: PermissionSnapshot
    @Published private(set) var permissionRequest: PermissionRequestState = .idle
    @Published private(set) var hotkeyHealth: HotkeyHealth

    private let interactor: DictationInteracting
    private let permissionManager: PermissionManaging
    private let router: AppRouter
    private var cancellables = Set<AnyCancellable>()
    private var permissionRequestTask: Task<Void, Never>?
    private var activationRefreshTask: Task<Void, Never>?
    private var permissionRequestGeneration = 0
    private var activationRefreshGeneration = 0

    private static let activationRefreshAttempts = 6
    private static let activationRefreshDelayNanoseconds: UInt64 = 100_000_000

    init(
        interactor: DictationInteracting,
        relay: DictationStateRelay,
        hotkeyRelay: HotkeyHealthRelay,
        permissionManager: PermissionManaging,
        router: AppRouter
    ) {
        self.interactor = interactor
        self.permissionManager = permissionManager
        self.router = router
        permissions = permissionManager.snapshot()
        hotkeyHealth = hotkeyRelay.health
        relay.$state.assign(to: &$state)
        hotkeyRelay.$health.assign(to: &$hotkeyHealth)
    }

    deinit {
        permissionRequestTask?.cancel()
        activationRefreshTask?.cancel()
    }

    var statusTitle: String {
        switch state {
        case .idle: "Idle"
        case .preparing: "Preparing…"
        case .recording: "Recording…"
        case .processing: "Processing on this Mac…"
        case .inserting: "Inserting…"
        case .failed(let failure): failure.message
        }
    }

    var statusDetail: String? {
        if case .failed(let failure) = state { return failure.recovery }
        return nil
    }

    var permissionRequestMessage: String? {
        switch permissionRequest {
        case .idle:
            nil
        case .requesting(let permission):
            "Requesting \(permission.title)… macOS is checking this permission."
        case .completed(let permission, _):
            completionMessage(for: permission, status: permissions[permission])
        }
    }

    func permissionRequestMessage(for permission: AppPermission) -> String? {
        switch permissionRequest {
        case .requesting(let requestedPermission), .completed(let requestedPermission, _):
            guard requestedPermission == permission else { return nil }
            return permissionRequestMessage
        case .idle:
            return nil
        }
    }

    func beginPushToTalk() { interactor.beginPushToTalk() }
    func endPushToTalk() { interactor.endPushToTalk() }
    func refreshPermissions() { permissions = permissionManager.snapshot() }

    func reconcilePermissionsAfterActivation() {
        activationRefreshTask?.cancel()
        activationRefreshGeneration &+= 1
        let generation = activationRefreshGeneration

        refreshPermissions()
        guard OnboardingProgress(permissions: permissions) != .ready else { return }

        let permissionManager = permissionManager
        activationRefreshTask = Task { [weak self] in
            for _ in 0..<Self.activationRefreshAttempts {
                do {
                    try await Task.sleep(nanoseconds: Self.activationRefreshDelayNanoseconds)
                } catch {
                    return
                }
                guard !Task.isCancelled, let self,
                      self.activationRefreshGeneration == generation else {
                    return
                }

                let snapshot = permissionManager.snapshot()
                self.permissions = snapshot
                if OnboardingProgress(permissions: snapshot) == .ready {
                    break
                }
            }

            guard let self, self.activationRefreshGeneration == generation else { return }
            self.activationRefreshTask = nil
        }
    }

    func request(_ permission: AppPermission) {
        permissionRequestTask?.cancel()
        permissionRequestGeneration &+= 1
        let generation = permissionRequestGeneration
        permissionRequest = .requesting(permission)

        let permissionManager = permissionManager
        permissionRequestTask = Task { [weak self] in
            _ = await permissionManager.request(permission)
            guard !Task.isCancelled, let self,
                  self.permissionRequestGeneration == generation else {
                return
            }

            let snapshot = permissionManager.snapshot()
            self.permissions = snapshot
            let publishedStatus = snapshot[permission]
            // The shared snapshot remains the source of truth if TCC settles
            // between the request API returning and this read.
            self.permissionRequest = .completed(permission, publishedStatus)
            self.permissionRequestTask = nil
        }
    }

    func openSystemSettings(for permission: AppPermission) {
        router.openSystemSettings(for: permission)
    }

    func quit() { NSApplication.shared.terminate(nil) }

    private func completionMessage(for permission: AppPermission, status: PermissionStatus) -> String {
        switch (permission, status) {
        case (_, .authorized):
            "\(permission.title) access is allowed."
        case (.inputMonitoring, .denied):
            inputMonitoringRegistrationFeedback()
        case (.accessibility, .denied):
            accessibilityRegistrationFeedback()
        case (.microphone, .denied):
            "Microphone access is still denied. Open System Settings to enable it."
        case (_, .restricted):
            "\(permission.title) is restricted by macOS and cannot be enabled here."
        case (_, .notDetermined):
            "macOS did not finish the \(permission.title) request. Try again or open System Settings."
        }
    }

    private func inputMonitoringRegistrationFeedback() -> String {
        "macOS still reports Input Monitoring as not authorized for this running WinterVoice copy. A request may not show another prompt after denial. Open System Settings to inspect the matching entry; enable it only if this copy is listed. If no WinterVoice entry appears, close other copies and relaunch this copy before trying again."
    }

    private func accessibilityRegistrationFeedback() -> String {
        "macOS still reports Accessibility as not authorized for this running WinterVoice copy. Open System Settings to inspect the matching entry; enable it only if this copy is listed. If no WinterVoice entry appears, close other copies and relaunch this copy before trying again."
    }
}
