import SwiftUI

struct SettingsView: View {
    @ObservedObject var presenter: DictationPresenter

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                Text("WinterVoice").font(.title2.bold())
                Text("Configure permissions here. Transcription provider mode and credentials are managed in the main WinterVoice window.")
                    .foregroundStyle(.secondary)
            }

            PermissionsView(presenter: presenter, showsIntroduction: false)
        }
        .padding(24)
        .frame(width: 620, height: 470)
        .onAppear { presenter.refreshPermissions() }
    }
}
