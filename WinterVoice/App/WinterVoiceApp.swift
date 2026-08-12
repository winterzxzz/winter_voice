import SwiftUI

@main
struct WinterVoiceApp: App {
    @NSApplicationDelegateAdaptor private var appDelegate: AppLifecycleController
    @State private var container: AppContainer

    init() {
        let container = AppContainer()
        _container = State(initialValue: container)
        appDelegate.didBecomeActive = { [weak container] in container?.start() }
        container.start()
    }

    var body: some Scene {
        Window("WinterVoice", id: "main") {
            LaunchGateView(
                onboardingPresenter: container.onboardingPresenter,
                shellPresenter: container.shellPresenter
            )
        }
        .defaultSize(width: 920, height: 640)
        .windowResizability(.contentMinSize)
        .commands {
            WinterVoiceCommands()
        }

        MenuBarExtra("WinterVoice", systemImage: "mic.fill") {
            MenuBarView(
                presenter: container.presenter,
                shellPresenter: container.shellPresenter
            )
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(presenter: container.presenter)
        }
    }
}

private struct WinterVoiceCommands: Commands {
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button("Open WinterVoice") {
                NSApplication.shared.activate(ignoringOtherApps: true)
                openWindow(id: "main")
            }
            .keyboardShortcut("0", modifiers: .command)
        }
    }
}
