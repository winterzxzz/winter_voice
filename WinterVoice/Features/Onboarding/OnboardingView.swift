import SwiftUI

struct OnboardingView: View {
    @ObservedObject var presenter: OnboardingPresenter
    @ObservedObject private var dictationPresenter: DictationPresenter

    init(presenter: OnboardingPresenter) {
        self.presenter = presenter
        _dictationPresenter = ObservedObject(wrappedValue: presenter.dictationPresenter)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                introduction
                nextStep

                VStack(spacing: 0) {
                    ForEach(AppPermission.allCases) { permission in
                        permissionRow(permission)
                        if permission != AppPermission.allCases.last { Divider() }
                    }
                }
                .padding(.horizontal, 18)
                .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))

                footer
            }
            .frame(maxWidth: 680, alignment: .leading)
            .padding(40)
        }
        .frame(minWidth: 760, minHeight: 520)
        .onAppear { presenter.refresh() }
    }

    private var introduction: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: "waveform.badge.mic")
                .font(.system(size: 38))
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
            Text("Set up WinterVoice")
                .font(.largeTitle.bold())
            Text("Four macOS permissions enable push-to-talk, private on-device speech recognition, and safe insertion into the field where dictation began.")
                .font(.title3)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var nextStep: some View {
        switch presenter.progress {
        case .ready:
            Label("All required permissions are allowed.", systemImage: "checkmark.circle.fill")
                .font(.headline)
                .foregroundStyle(.green)
        case .needsPermission(let permission):
            VStack(alignment: .leading, spacing: 10) {
                Text("Next: Allow \(permission.title)")
                    .font(.headline)
                Text(nextStepExplanation(for: permission))
                    .foregroundStyle(.secondary)
                Button(nextActionTitle(for: permission)) {
                    presenter.performNextAction()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
        }
    }

    private func permissionRow(_ permission: AppPermission) -> some View {
        let status = dictationPresenter.permissions[permission]
        return HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon(for: permission))
                .font(.title3)
                .frame(width: 28)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text(permission.title).font(.headline)
                    Label(status.rawValue, systemImage: status == .authorized
                        ? "checkmark.circle.fill"
                        : "exclamationmark.circle")
                        .font(.caption.bold())
                        .foregroundStyle(status == .authorized ? .green : .secondary)
                }
                Text(permission.explanation)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if requiresPossibleRelaunch(permission), status != .authorized {
                    Text("After enabling this in System Settings, return to WinterVoice. If macOS says the change needs a restart—or the status does not update—quit and relaunch this same signed build.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 12)
            if status != .authorized {
                Button(rowActionTitle(for: permission, status: status)) {
                    if status == .notDetermined || requiresPossibleRelaunch(permission) {
                        presenter.request(permission)
                    } else {
                        presenter.openSystemSettings(for: permission)
                    }
                }
            }
        }
        .padding(.vertical, 16)
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Button("Refresh Status") { presenter.refresh() }
                Spacer()
                if presenter.progress == .ready {
                    Button("Start Using WinterVoice") { presenter.complete() }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                } else {
                    Button("Use With Limitations") { presenter.deferForNow() }
                        .controlSize(.large)
                }
            }
            if presenter.progress != .ready {
                Text("You can continue now, but unavailable permissions will prevent some or all dictation steps. Nothing is marked complete, and you can reopen this guide from Permissions in the main window.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func nextActionTitle(for permission: AppPermission) -> String {
        let status = dictationPresenter.permissions[permission]
        if status == .notDetermined { return "Request \(permission.title)" }
        if requiresPossibleRelaunch(permission) { return "Request or Open System Settings" }
        return "Open System Settings"
    }

    private func rowActionTitle(for permission: AppPermission, status: PermissionStatus) -> String {
        if status == .notDetermined { return "Request" }
        if requiresPossibleRelaunch(permission) { return "Request Access" }
        return "Open Settings"
    }

    private func nextStepExplanation(for permission: AppPermission) -> String {
        if requiresPossibleRelaunch(permission) {
            return "macOS manages this permission in Privacy & Security. WinterVoice will request access and open the relevant System Settings page if it is not immediately available."
        }
        return dictationPresenter.permissions[permission] == .notDetermined
            ? "macOS will show a system permission prompt."
            : "This permission was declined or restricted. Change it in Privacy & Security to continue."
    }

    private func requiresPossibleRelaunch(_ permission: AppPermission) -> Bool {
        permission == .inputMonitoring || permission == .accessibility
    }

    private func icon(for permission: AppPermission) -> String {
        switch permission {
        case .microphone: "mic"
        case .speechRecognition: "waveform"
        case .inputMonitoring: "keyboard.badge.eye"
        case .accessibility: "accessibility"
        }
    }
}
