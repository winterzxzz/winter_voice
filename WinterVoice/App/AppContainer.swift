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
    let hotkeyBinding: HotkeyBindingStore
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
        let hotkeyBinding = HotkeyBindingStore()
        self.providerConfiguration = providerConfiguration
        self.modelManager = modelManager
        self.history = history
        self.dictionary = dictionary
        self.hotkeyBinding = hotkeyBinding
        let whisperRuntime = WhisperContextActor()
        modelManager.localRuntimeUnloader = {
            Task { await whisperRuntime.unloadContext() }
        }
        providerConfiguration.onModeChange = { mode in
            guard mode == .remote else { return }
            Task { await whisperRuntime.unloadContext() }
        }
        let audioRecorder = SystemAudioRecorder()
        let usageStats = UsageStatsStore()
        let interactor = DictationInteractor(
            relay: relay,
            transcriber: ConfiguredTranscriber(
                recorder: audioRecorder,
                configuration: providerConfiguration,
                models: modelManager,
                localRuntime: whisperRuntime
            ),
            injector: SystemTextInjector(),
            permissions: permissionManager,
            textProcessor: dictionary,
            history: history,
            usage: usageStats
        )
        let router = AppRouter()
        let presenter = DictationPresenter(
            interactor: interactor,
            relay: relay,
            hotkeyRelay: hotkeyRelay,
            permissionManager: permissionManager,
            router: router,
            hotkeyBinding: hotkeyBinding
        )
        self.presenter = presenter
        let hotkey = RightOptionEventTap(
            interactor: interactor,
            relay: hotkeyRelay,
            binding: hotkeyBinding
        )
        self.hotkey = hotkey
        shellPresenter = AppShellPresenter(
            dictationPresenter: presenter,
            router: router,
            providerConfiguration: providerConfiguration,
            modelManager: modelManager,
            history: history,
            dictionary: dictionary,
            hotkeyBinding: hotkeyBinding,
            usageStats: usageStats,
            hotkeyCaptureSuspender: hotkey
        )
        onboardingPresenter = OnboardingPresenter(
            dictationPresenter: presenter,
            interactor: OnboardingInteractor(
                completionStore: UserDefaultsOnboardingCompletionStore()
            )
        )
        permissionHotkeyReconciler = PermissionHotkeyReconciler(
            presenter: presenter,
            hotkey: hotkey
        )
        panelController = RecordingPanelController(
            presenter: presenter,
            levelMeter: audioRecorder.levelMeter
        )
    }

    func start() {
        presenter.reconcilePermissionsAfterActivation()
    }
}
