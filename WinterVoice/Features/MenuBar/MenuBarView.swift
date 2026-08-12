import SwiftUI

struct MenuBarView: View {
    @ObservedObject var presenter: DictationPresenter
    @ObservedObject var shellPresenter: AppShellPresenter
    @Environment(\.openSettings) private var openSettings
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(presenter.statusTitle, systemImage: presenter.state == .recording ? "waveform" : "mic")
            Divider()
            Text("Hold Right Option to dictate")
                .font(.caption)
                .foregroundStyle(.secondary)
            Label(
                presenter.hotkeyHealth.title,
                systemImage: presenter.hotkeyHealth == .listening ? "keyboard" : "exclamationmark.triangle"
            )
            .font(.caption)
            .foregroundStyle(presenter.hotkeyHealth == .listening ? Color.secondary : Color.orange)
            Button("Open WinterVoice") {
                shellPresenter.activateApplication()
                openWindow(id: "main")
            }
            .keyboardShortcut("0", modifiers: .command)
            Button("Settings…") { openSettings() }
                .keyboardShortcut(",")
            Divider()
            Button("Quit WinterVoice") { presenter.quit() }
                .keyboardShortcut("q")
        }
        .padding(12)
        .frame(width: 250)
    }
}
