import SwiftUI

struct MenuBarView: View {
    @ObservedObject var presenter: DictationPresenter
    @ObservedObject var shellPresenter: AppShellPresenter
    @ObservedObject var onboardingPresenter: OnboardingPresenter
    @Environment(\.openSettings) private var openSettings
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Label(
            presenter.statusTitle,
            systemImage: presenter.state == .recording ? "waveform" : "mic"
        )
        .disabled(true)

        Label(
            presenter.hotkeyHealthTitle,
            systemImage: presenter.hotkeyHealth == .listening
                ? "keyboard" : "exclamationmark.triangle"
        )
        .disabled(true)

        Text(shellPresenter.providerStatus.isReady
            ? presenter.hotkeyInstruction
            : "Transcription provider not ready")
            .disabled(true)

        Divider()

        Button("Open WinterVoice") {
            openMainWindow()
        }
        .keyboardShortcut("0", modifiers: .command)

        Button("Open Permission Guide…") {
            onboardingPresenter.restart()
            openMainWindow()
        }

        Button("Settings…") { openSettings() }
            .keyboardShortcut(",")

        Button(updateMenuTitle) {
            shellPresenter.updates.checkNow()
            shellPresenter.navigate(to: .settings)
            openMainWindow()
        }

        Divider()

        Button("Quit WinterVoice") { presenter.quit() }
            .keyboardShortcut("q")
    }

    private var updateMenuTitle: String {
        if shellPresenter.updates.state.isInstallBusy {
            return "Updating WinterVoice…"
        }
        if case .available(let update) = shellPresenter.updates.state {
            return "Update Available: v\(update.version)…"
        }
        return "Check for Updates…"
    }

    private func openMainWindow() {
        shellPresenter.activateApplication()
        openWindow(id: "main")
    }
}
