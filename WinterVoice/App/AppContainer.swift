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
        // Dev affordance: `open WinterVoice.app --args -WVOpenPage settings`
        // jumps straight to a shell page on launch.
        let arguments = ProcessInfo.processInfo.arguments
        if let flagIndex = arguments.firstIndex(of: "-WVOpenPage"),
           let destination = AppShellDestination(rawValue: arguments.dropFirst(flagIndex + 1).first ?? "") {
            router.navigate(to: destination)
        }
        // Dev affordance: `-WVThemeFlipAfter 3` toggles Black/Light once after
        // N seconds, so live theme switching is verifiable in screenshot runs.
        if let flagIndex = arguments.firstIndex(of: "-WVThemeFlipAfter"),
           let delay = TimeInterval(arguments.dropFirst(flagIndex + 1).first ?? "") {
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                let store = ThemeStore.shared
                store.mode = store.mode == .black ? .light : .black
            }
        }
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
        let widgetPreferences = WidgetPreferences()
        shellPresenter = AppShellPresenter(
            dictationPresenter: presenter,
            router: router,
            providerConfiguration: providerConfiguration,
            modelManager: modelManager,
            history: history,
            dictionary: dictionary,
            hotkeyBinding: hotkeyBinding,
            usageStats: usageStats,
            widgetPreferences: widgetPreferences,
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
        let panel = RecordingPanelController(
            presenter: presenter,
            levelMeter: audioRecorder.levelMeter,
            preferences: widgetPreferences
        )
        panelController = panel
        hotkey.onShowWidget = { [weak panel] in panel?.showWidget() }
    }

    func start() {
        presenter.reconcilePermissionsAfterActivation()
    }
}
