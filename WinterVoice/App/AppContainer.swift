import Foundation

@MainActor
final class AppContainer {
    let presenter: DictationPresenter
    let shellPresenter: AppShellPresenter
    private let hotkey: RightOptionEventTap
    private let panelController: RecordingPanelController

    init() {
        let relay = DictationStateRelay()
        let hotkeyRelay = HotkeyHealthRelay()
        let permissionManager = SystemPermissionManager()
        let interactor = DictationInteractor(
            relay: relay,
            transcriber: AppleSpeechTranscriber(),
            injector: SystemTextInjector(),
            permissions: permissionManager
        )
        let router = AppRouter()
        let presenter = DictationPresenter(
            interactor: interactor,
            relay: relay,
            hotkeyRelay: hotkeyRelay,
            permissionManager: permissionManager,
            router: router
        )
        self.presenter = presenter
        shellPresenter = AppShellPresenter(
            dictationPresenter: presenter,
            interactor: AppShellInteractor(),
            router: router
        )
        hotkey = RightOptionEventTap(interactor: interactor, relay: hotkeyRelay)
        panelController = RecordingPanelController(presenter: presenter)
    }

    func start() {
        presenter.refreshPermissions()
        hotkey.reconcile()
    }
}
