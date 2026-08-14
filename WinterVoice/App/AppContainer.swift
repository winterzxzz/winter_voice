import AppKit
import Combine
import Foundation
import SwiftUI

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
        let microphonePreferences = MicrophonePreferences()
        let audioRecorder = SystemAudioRecorder(preferences: microphonePreferences)
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
        // Dev affordance: `-WVWidgetDemo` loops the widget through the
        // dictation states with synthetic voice levels, so the recording
        // waveform is filmable without microphone or hotkey permissions.
        if arguments.contains("-WVWidgetDemo") {
            let demoLevelMeter = audioRecorder.levelMeter
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                while !Task.isCancelled {
                    relay.publish(.preparing)
                    try? await Task.sleep(nanoseconds: 800_000_000)
                    relay.publish(.recording)
                    let recordingStart = Date()
                    while Date().timeIntervalSince(recordingStart) < 4.2 {
                        let time = Date().timeIntervalSinceReferenceDate
                        // Bursts separated by pauses so the bars read as speech.
                        let speaking = sin(time * 1.9) > -0.35
                        let level = speaking
                            ? Float(0.2 + 0.65 * abs(sin(time * 9.3) * sin(time * 3.7)))
                            : Float(0.04)
                        demoLevelMeter.update(level)
                        try? await Task.sleep(nanoseconds: 40_000_000)
                    }
                    relay.publish(.processing)
                    try? await Task.sleep(nanoseconds: 1_500_000_000)
                    relay.publish(.inserting)
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                    relay.publish(.idle)
                    try? await Task.sleep(nanoseconds: 2_500_000_000)
                }
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
            microphonePreferences: microphonePreferences,
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
        // Dev affordance: `-WVWidgetFrames <dir>` renders the widget's state
        // cycle to numbered PNG frames offscreen and exits — asset shoots
        // never depend on live screen capture or the cursor-following panel.
        if let flagIndex = arguments.firstIndex(of: "-WVWidgetFrames"),
           let framesPath = arguments.dropFirst(flagIndex + 1).first {
            let demoLevelMeter = audioRecorder.levelMeter
            let framesPresenter = presenter
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                let directory = URL(fileURLWithPath: framesPath, isDirectory: true)
                try? FileManager.default.createDirectory(
                    at: directory, withIntermediateDirectories: true
                )
                let fps = 10.0
                let schedule: [(DictationState, Double)] = [
                    (.idle, 1.2), (.preparing, 0.8), (.recording, 4.0),
                    (.processing, 1.5), (.inserting, 1.0), (.idle, 1.5),
                ]
                var frame = 0
                for (state, duration) in schedule {
                    relay.publish(state)
                    for _ in 0..<Int(duration * fps) {
                        let time = Date().timeIntervalSinceReferenceDate
                        if state == .recording {
                            let speaking = sin(time * 1.9) > -0.35
                            demoLevelMeter.update(
                                speaking
                                    ? Float(0.2 + 0.65 * abs(sin(time * 9.3) * sin(time * 3.7)))
                                    : Float(0.04)
                            )
                        }
                        let scene = ZStack {
                            LinearGradient(
                                colors: [Color(hex: 0x101014), Color(hex: 0x1C1C22)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                            RecordingPanelView(
                                presenter: framesPresenter,
                                levelMeter: demoLevelMeter,
                                usesSnapshotSpinner: true
                            )
                        }
                        .frame(width: 360, height: 110)
                        let renderer = ImageRenderer(content: scene)
                        renderer.scale = 2
                        if let image = renderer.nsImage,
                           let tiff = image.tiffRepresentation,
                           let rep = NSBitmapImageRep(data: tiff),
                           let png = rep.representation(using: .png, properties: [:]) {
                            let name = String(format: "f%04d.png", frame)
                            try? png.write(to: directory.appendingPathComponent(name))
                        }
                        frame += 1
                        try? await Task.sleep(nanoseconds: UInt64(1_000_000_000 / fps))
                    }
                }
                exit(0)
            }
        }
    }

    func start() {
        presenter.reconcilePermissionsAfterActivation()
    }
}
