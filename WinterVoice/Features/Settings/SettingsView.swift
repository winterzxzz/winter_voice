import SwiftUI

struct SettingsView: View {
    @ObservedObject var presenter: DictationPresenter

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("WinterVoice")
                    .font(.wvTitle)
                    .foregroundStyle(Theme.textPrimary)
                Text("Configure permissions here. Transcription provider mode and credentials are managed in the main WinterVoice window.")
                    .font(.wvBody)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            PermissionsView(presenter: presenter, showsIntroduction: false)
        }
        .padding(24)
        .frame(width: 620, height: 470)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.canvas)
        .tint(Theme.accent)
        .preferredColorScheme(.dark)
        .onAppear { presenter.refreshPermissions() }
    }
}
