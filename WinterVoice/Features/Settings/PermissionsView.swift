import SwiftUI

struct PermissionsView: View {
    @ObservedObject var presenter: DictationPresenter
    var showsIntroduction = true
    var reopenOnboarding: (() -> Void)?

    var body: some View {
        if showsIntroduction {
            WVPage(
                icon: "checkmark.shield",
                title: "Permissions",
                subtitle: "Microphone, Input Monitoring, and Accessibility are required for audio capture, the global hotkey, and safe insertion."
            ) {
                cards
            }
            .onAppear { presenter.refreshPermissions() }
        } else {
            // Embedded (inside the Settings page or the Cmd+, window): no page
            // header, just the cards; the host provides scrolling.
            VStack(alignment: .leading, spacing: Theme.Space.md) {
                cards
            }
            .onAppear { presenter.refreshPermissions() }
        }
    }

    @ViewBuilder
    private var cards: some View {
        WVCard {
            VStack(spacing: 0) {
                ForEach(Array(AppPermission.allCases.enumerated()), id: \.offset) { index, permission in
                    if index > 0 { WVDivider().padding(.vertical, 13) }
                    permissionRow(permission)
                }
            }
        }

        if let reopenOnboarding {
            WVCard {
                HStack(alignment: .top, spacing: Theme.Space.sm) {
                    WVIconBadge(systemImage: "sparkles")
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Permission Guide")
                            .font(.wvHeadline)
                            .foregroundStyle(Theme.textPrimary)
                        Text("Reopen the guided setup at any time. This resets the saved onboarding completion marker, but does not change macOS permissions.")
                            .font(.wvBody)
                            .foregroundStyle(Theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Button("Open Permission Guide") { reopenOnboarding() }
                            .buttonStyle(.wvSecondary)
                            .padding(.top, 2)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }

    private func permissionRow(_ permission: AppPermission) -> some View {
        let status = presenter.permissions[permission]
        let authorized = status == .authorized
        return HStack(alignment: .top, spacing: Theme.Space.sm) {
            WVIconBadge(
                systemImage: icon(for: permission),
                tint: authorized ? Theme.success : Theme.textSecondary
            )
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(permission.title)
                        .font(.wvRowTitle)
                        .foregroundStyle(Theme.textPrimary)
                    WVStatusPill(
                        text: status.rawValue,
                        color: authorized ? Theme.success : Theme.warning,
                        filled: true
                    )
                }
                Text(permission.explanation)
                    .font(.wvBody)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: Theme.Space.md)
            VStack(alignment: .trailing, spacing: 6) {
                permissionAction(permission)
                if let requestMessage = presenter.permissionRequestMessage(for: permission) {
                    Text(requestMessage)
                        .font(.wvCaption)
                        .foregroundStyle(Theme.textSecondary)
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 180, alignment: .trailing)
                }
            }
        }
    }

    @ViewBuilder
    private func permissionAction(_ permission: AppPermission) -> some View {
        let status = presenter.permissions[permission]
        if status != .authorized {
            HStack(spacing: 8) {
                if status == .notDetermined || permission == .inputMonitoring || permission == .accessibility {
                    Button("Request") { presenter.request(permission) }
                        .buttonStyle(.wvPrimary)
                }
                if status != .notDetermined || permission == .inputMonitoring || permission == .accessibility {
                    Button("Open Settings") { presenter.openSystemSettings(for: permission) }
                        .buttonStyle(.wvSecondary)
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
