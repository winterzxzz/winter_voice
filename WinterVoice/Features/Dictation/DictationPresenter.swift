import AppKit
import Combine

@MainActor
final class DictationPresenter: ObservableObject {
    @Published private(set) var state: DictationState = .idle
    @Published private(set) var permissions: PermissionSnapshot
    @Published private(set) var hotkeyHealth: HotkeyHealth

    private let interactor: DictationInteracting
    private let permissionManager: PermissionManaging
    private let router: AppRouter
    private var cancellables = Set<AnyCancellable>()

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

    var statusTitle: String {
        switch state {
        case .idle: "Ready"
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

    func beginPushToTalk() { interactor.beginPushToTalk() }
    func endPushToTalk() { interactor.endPushToTalk() }
    func refreshPermissions() { permissions = permissionManager.snapshot() }

    func request(_ permission: AppPermission) {
        Task {
            let status = await permissionManager.request(permission)
            permissions = permissionManager.snapshot()
            if status != .authorized { router.openSystemSettings(for: permission) }
        }
    }

    func openSystemSettings(for permission: AppPermission) {
        router.openSystemSettings(for: permission)
    }

    func quit() { NSApplication.shared.terminate(nil) }
}
