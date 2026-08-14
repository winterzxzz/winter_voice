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
        VStack(spacing: 0) {
            header
            Spacer(minLength: 20)
            heroCard(for: permission, status: status)
            Spacer(minLength: 20)
            footer
        }
        .padding(36)
        .frame(minWidth: 760, minHeight: 560)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            ZStack {
                WVCanvasBackground()
                // The splash's accent bloom carries into setup so the two
                // screens read as one welcome sequence.
                RadialGradient(
                    colors: [Theme.accent.opacity(0.10), .clear],
                    center: .top,
                    startRadius: 20,
                    endRadius: 420
                )
            }
            .ignoresSafeArea()
        }
        .tint(Theme.accent)
        .preferredColorScheme(Theme.mode.colorScheme)
        .wvWindowChrome()
        .onAppear { presenter.refresh() }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            WVBrandMark(size: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text("Set up WinterVoice")
                    .font(.wv(21, .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text("Three permissions, then your voice types everywhere.")
                    .font(.wvCaption)
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer()
            stepChips
        }
    }

    private var stepChips: some View {
        HStack(spacing: 8) {
            ForEach(Array(AppPermission.allCases.enumerated()), id: \.element) { index, permission in
                let isAuthorized = dictationPresenter.permissions[permission] == .authorized
                let isCurrent = index == presenter.pageIndex
                HStack(spacing: 5) {
                    Image(systemName: isAuthorized ? "checkmark.circle.fill" : icon(for: permission))
                        .font(.system(size: 11, weight: .semibold))
                    Text(permission.title)
                        .font(.wv(11, .medium))
                        .lineLimit(1)
                }
                .foregroundStyle(
                    isAuthorized ? Theme.success : isCurrent ? Theme.textPrimary : Theme.textTertiary
                )
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background {
                    if isCurrent {
                        Capsule()
                            .fill(Theme.surfaceElevated)
                            .overlay(Capsule().strokeBorder(Theme.borderStrong, lineWidth: 1))
                    }
                }
            }
        }
    }

    // MARK: - Hero

    private func heroCard(for permission: AppPermission, status: PermissionStatus) -> some View {
        WVCard(padding: 30) {
            VStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(Theme.accent.opacity(0.16))
                        .frame(width: 112, height: 112)
                        .blur(radius: 26)
                    WVIconBadge(systemImage: icon(for: permission), tint: Theme.accent, size: 64)
                }
                .padding(.top, 4)

                Text(permission.title)
                    .font(.wv(24, .semibold))
                    .foregroundStyle(Theme.textPrimary)

                Text(permission.explanation)
                    .font(.wv(13.5))
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 440)

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
                    .padding(.top, 4)

                    Text(recoveryText(for: permission, status: status))
                        .font(.wvCaption)
                        .foregroundStyle(Theme.textTertiary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: 500)
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
                    .multilineTextAlignment(.center)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: 620)
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(spacing: 10) {
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
                .frame(maxWidth: .infinity, alignment: .leading)
        }
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
