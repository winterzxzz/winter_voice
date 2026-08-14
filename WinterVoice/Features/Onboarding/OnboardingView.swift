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
        let total = AppPermission.allCases.count
        VStack(alignment: .leading, spacing: 24) {
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(LinearGradient(colors: [Theme.accent, Color(hex: 0x1D4ED8)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 34, height: 34)
                    .overlay(Image(systemName: "waveform").font(.system(size: 16, weight: .bold)).foregroundStyle(.white))
                VStack(alignment: .leading, spacing: 1) {
                    Text("Set up WinterVoice").font(.wv(22, .semibold)).foregroundStyle(Theme.textPrimary)
                    Text("Step \(presenter.pageIndex + 1) of \(total)").font(.wvCaption).foregroundStyle(Theme.textSecondary)
                }
                Spacer()
            }

            ProgressView(value: Double(presenter.pageIndex + 1), total: Double(total))
                .tint(Theme.accent)

            WVCard(padding: 24) {
                VStack(alignment: .leading, spacing: 14) {
                    WVIconBadge(systemImage: icon(for: permission), tint: Theme.accent, size: 48)
                    Text(permission.title).font(.wv(20, .semibold)).foregroundStyle(Theme.textPrimary)
                    Text(permission.explanation)
                        .font(.wv(14))
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    WVStatusPill(
                        text: status.rawValue,
                        color: status == .authorized ? Theme.success : Theme.warning,
                        filled: true
                    )

                    if status != .authorized {
                        HStack(spacing: 10) {
                            if status == .notDetermined || requiresSystemManagedRequest(permission) {
                                Button("Request \(permission.title)") { presenter.request(permission) }
                                    .buttonStyle(.wvPrimary)
                            }
                            if status != .notDetermined || requiresSystemManagedRequest(permission) {
                                Button("Open System Settings") { presenter.openSystemSettings(for: permission) }
                                    .buttonStyle(.wvSecondary)
                            }
                        }
                        .padding(.top, 2)
                        Text(recoveryText(for: permission, status: status))
                            .font(.wvCaption)
                            .foregroundStyle(Theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if let requestMessage = dictationPresenter.permissionRequestMessage(for: permission) {
                        Label(
                            requestMessage,
                            systemImage: requestMessage.hasPrefix("Requesting")
                                ? "arrow.triangle.2.circlepath"
                                : status == .authorized ? "checkmark.circle.fill" : "info.circle"
                        )
                        .font(.wvCaption)
                        .foregroundStyle(status == .authorized ? Theme.success : Theme.textSecondary)
                    }
                }
            }

            Spacer()
            HStack(spacing: 10) {
                Button("Back") { presenter.back() }
                    .buttonStyle(.wvGhost)
                    .disabled(!presenter.canGoBack)
                Button("Use With Limitations") { presenter.deferForNow() }
                    .buttonStyle(.wvGhost)
                Spacer()
                Button("Refresh Status") { presenter.refresh() }
                    .buttonStyle(.wvSecondary)
                Button(presenter.isLastPage ? "Start Using WinterVoice" : "Next") { presenter.next() }
                    .buttonStyle(.wvPrimary)
                    .disabled(presenter.isLastPage && presenter.progress != .ready)
            }
            Text("Deferring never marks setup complete. Reopen this guide from Permissions at any time.")
                .font(.wvCaption)
                .foregroundStyle(Theme.textTertiary)
        }
        .padding(40)
        .frame(minWidth: 760, minHeight: 520)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.canvas)
        .tint(Theme.accent)
        .preferredColorScheme(.dark)
        .wvWindowChrome()
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
