import Foundation
import Combine

@MainActor
final class PermissionHotkeyReconciler {
    private let cancellable: AnyCancellable

    init(presenter: DictationPresenter, hotkey: HotkeyReconciling) {
        cancellable = presenter.$permissions
            .removeDuplicates()
            .sink { _ in hotkey.reconcile() }
    }
}

@MainActor
final class AppContainer {
    let presenter: DictationPresenter
    let shellPresenter: AppShellPresenter
    let onboardingPresenter: OnboardingPresenter
    let providerConfiguration: ProviderConfigurationStore
    let modelManager: ModelManager
    let history: HistoryStore
    let dictionary: DictionaryStore
    private let hotkey: RightOptionEventTap
    private let permissionHotkeyReconciler: PermissionHotkeyReconciler
    private let panelController: RecordingPanelController

    init() {
        let relay = DictationStateRelay()
        let hotkeyRelay = HotkeyHealthRelay()
        let permissionManager = SystemPermissionManager()
        let providerConfiguration = ProviderConfigurationStore()
        let modelManager = ModelManager()
        let history = HistoryStore()
        let dictionary = DictionaryStore()
        self.providerConfiguration = providerConfiguration
        self.modelManager = modelManager
        self.history = history
        self.dictionary = dictionary
        let interactor = DictationInteractor(
            relay: relay,
            transcriber: ConfiguredTranscriber(
                recorder: SystemAudioRecorder(),
                configuration: providerConfiguration,
                models: modelManager
            ),
            injector: SystemTextInjector(),
            permissions: permissionManager,
            textProcessor: dictionary,
            history: history
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
            router: router,
            providerConfiguration: providerConfiguration,
            modelManager: modelManager,
            history: history,
            dictionary: dictionary
        )
        onboardingPresenter = OnboardingPresenter(
            dictationPresenter: presenter,
            interactor: OnboardingInteractor(
                completionStore: UserDefaultsOnboardingCompletionStore()
            )
        )
        let hotkey = RightOptionEventTap(interactor: interactor, relay: hotkeyRelay)
        self.hotkey = hotkey
        permissionHotkeyReconciler = PermissionHotkeyReconciler(
            presenter: presenter,
            hotkey: hotkey
        )
        panelController = RecordingPanelController(presenter: presenter)
    }

    func start() {
        presenter.reconcilePermissionsAfterActivation()
    }
}
