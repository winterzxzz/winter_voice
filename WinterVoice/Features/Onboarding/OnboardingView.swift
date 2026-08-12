import SwiftUI

struct OnboardingView: View {
    @ObservedObject var presenter: OnboardingPresenter
    @ObservedObject private var dictationPresenter: DictationPresenter

    init(presenter: OnboardingPresenter) {
        self.presenter = presenter
        _dictationPresenter = ObservedObject(wrappedValue: presenter.dictationPresenter)
    }

    var body: some View {
        let permission = presenter.currentPermission
        let status = dictationPresenter.permissions[permission]
        VStack(alignment: .leading, spacing: 28) {
            HStack {
                Text("Set up WinterVoice").font(.largeTitle.bold())
                Spacer()
                Text("\(presenter.pageIndex + 1) of \(AppPermission.allCases.count)")
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: Double(presenter.pageIndex + 1), total: Double(AppPermission.allCases.count))

            VStack(alignment: .leading, spacing: 16) {
                Image(systemName: icon(for: permission))
                    .font(.system(size: 42))
                    .foregroundStyle(.tint)
                Text(permission.title).font(.title.bold())
                Text(permission.explanation)
                    .font(.title3)
                    .foregroundStyle(.secondary)
                Label(status.rawValue, systemImage: status == .authorized ? "checkmark.circle.fill" : "exclamationmark.circle")
                    .foregroundStyle(status == .authorized ? .green : .orange)

                if status != .authorized {
                    HStack {
                        if status == .notDetermined || requiresSystemManagedRequest(permission) {
                            Button("Request \(permission.title)") { presenter.request(permission) }
                                .buttonStyle(.borderedProminent)
                        }
                        if status != .notDetermined || requiresSystemManagedRequest(permission) {
                            Button("Open System Settings") { presenter.openSystemSettings(for: permission) }
                        }
                    }
                    Text(recoveryText(for: permission, status: status))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let requestMessage = dictationPresenter.permissionRequestMessage(for: permission) {
                    Label(
                        requestMessage,
                        systemImage: requestMessage.hasPrefix("Requesting")
                            ? "arrow.triangle.2.circlepath"
                            : status == .authorized ? "checkmark.circle.fill" : "info.circle"
                    )
                    .font(.caption)
                    .foregroundStyle(status == .authorized ? .green : .secondary)
                }
            }
            .padding(28)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 14))

            Spacer()
            HStack {
                Button("Back") { presenter.back() }.disabled(!presenter.canGoBack)
                Button("Use With Limitations") { presenter.deferForNow() }
                Spacer()
                Button("Refresh Status") { presenter.refresh() }
                Button(presenter.isLastPage ? "Start Using WinterVoice" : "Next") { presenter.next() }
                    .buttonStyle(.borderedProminent)
                    .disabled(presenter.isLastPage && presenter.progress != .ready)
            }
            Text("Deferring never marks setup complete. Reopen this guide from Permissions at any time.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(40)
        .frame(minWidth: 760, minHeight: 520)
        .onAppear { presenter.refresh() }
    }

    private func requiresSystemManagedRequest(_ permission: AppPermission) -> Bool {
        permission == .inputMonitoring || permission == .accessibility
    }

    private func recoveryText(for permission: AppPermission, status: PermissionStatus) -> String {
        switch permission {
        case .inputMonitoring:
            if status == .notDetermined {
                return "Request access. If macOS does not show a prompt, use Open System Settings. Return to WinterVoice; the status rechecks automatically."
            }
            return "macOS reports this running WinterVoice copy is not authorized. Input Monitoring may not show another prompt after denial; use Open System Settings to inspect the matching entry and enable it only if this copy is listed. If no entry appears, close other copies and relaunch this copy. Return to WinterVoice; the status rechecks automatically."
        case .accessibility:
            return status == .notDetermined
                ? "Request access so macOS can evaluate this copy. If no prompt appears, use Open System Settings. Return to WinterVoice; the status rechecks automatically."
                : "macOS reports this running WinterVoice copy is not authorized. Use Open System Settings to inspect the matching entry and enable it only if this copy is listed. If no entry appears, close other copies and relaunch this copy. Return to WinterVoice; the status rechecks automatically."
        case .microphone:
            return status == .notDetermined
                ? "macOS will show the Microphone privacy prompt."
                : "Access was declined or restricted. Use the explicit System Settings action to recover."
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
