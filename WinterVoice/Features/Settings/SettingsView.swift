import SwiftUI

struct SettingsView: View {
    @ObservedObject var presenter: DictationPresenter

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                Text("WinterVoice").font(.title2.bold())
                Text("Hold the Right Option key to record. Recognition stays on this Mac; unsupported languages fail instead of using a network service.")
                    .foregroundStyle(.secondary)
            }

            PermissionsView(presenter: presenter, showsIntroduction: false)
        }
        .padding(24)
        .frame(width: 620, height: 470)
        .onAppear { presenter.refreshPermissions() }
    }
}
