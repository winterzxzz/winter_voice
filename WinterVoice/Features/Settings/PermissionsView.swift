import SwiftUI

struct PermissionsView: View {
    @ObservedObject var presenter: DictationPresenter
    var showsIntroduction = true
    var reopenOnboarding: (() -> Void)?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                if showsIntroduction {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Permissions")
                            .font(.largeTitle)
                        Text("Microphone, Input Monitoring, and Accessibility are required for audio capture, the global hotkey, and safe insertion into another app.")
                            .foregroundStyle(.secondary)
                    }
                }

                ForEach(AppPermission.allCases) { permission in
                    permissionRow(permission)
                    if permission != AppPermission.allCases.last { Divider() }
                }

                if let reopenOnboarding {
                    Divider()
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Permission Guide")
                            .font(.headline)
                        Text("Reopen the guided setup at any time. This resets the saved onboarding completion marker, but does not change macOS permissions.")
                            .foregroundStyle(.secondary)
                        Button("Open Permission Guide") { reopenOnboarding() }
                    }
                }
            }
            .frame(maxWidth: 680, alignment: .leading)
            .padding(32)
        }
        .navigationTitle("Permissions")
        .onAppear { presenter.refreshPermissions() }
    }

    private func permissionRow(_ permission: AppPermission) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon(for: permission))
                .font(.title3)
                .frame(width: 28)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text(permission.title).font(.headline)
                    Text(presenter.permissions[permission].rawValue)
                        .font(.caption.bold())
                        .foregroundStyle(presenter.permissions[permission] == .authorized ? .green : .secondary)
                }
                Text(permission.explanation)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 16)
            VStack(alignment: .trailing, spacing: 6) {
                permissionAction(permission)
                if let requestMessage = presenter.permissionRequestMessage(for: permission) {
                    Text(requestMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.trailing)
                }
            }
        }
    }

    @ViewBuilder
    private func permissionAction(_ permission: AppPermission) -> some View {
        let status = presenter.permissions[permission]
        if status != .authorized {
            HStack {
                if status == .notDetermined || permission == .inputMonitoring || permission == .accessibility {
                    Button("Request") { presenter.request(permission) }
                }
                if status != .notDetermined || permission == .inputMonitoring || permission == .accessibility {
                    Button("Open Settings") {
                        presenter.openSystemSettings(for: permission)
                    }
                }
            }
        }
    }

    private func icon(for permission: AppPermission) -> String {
        switch permission {
        case .microphone: "mic"
        case .inputMonitoring: "keyboard.badge.eye"
        case .accessibility: "accessibility"
        }
    }
}
