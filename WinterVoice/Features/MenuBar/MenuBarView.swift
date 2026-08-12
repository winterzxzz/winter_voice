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
            presenter.hotkeyHealth.title,
            systemImage: presenter.hotkeyHealth == .listening
                ? "keyboard" : "exclamationmark.triangle"
        )
        .disabled(true)

        Text(shellPresenter.providerStatus.isReady
            ? "Hold Right Option to dictate"
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

        Divider()

        Button("Quit WinterVoice") { presenter.quit() }
            .keyboardShortcut("q")
    }

    private func openMainWindow() {
        shellPresenter.activateApplication()
        openWindow(id: "main")
    }
}
