import SwiftUI

struct OverviewView: View {
    @ObservedObject var presenter: AppShellPresenter
    @ObservedObject private var dictationPresenter: DictationPresenter

    init(presenter: AppShellPresenter) {
        self.presenter = presenter
        _dictationPresenter = ObservedObject(wrappedValue: presenter.dictationPresenter)
    }

    private var permissionsReady: Bool {
        AppPermission.allCases.allSatisfy {
            dictationPresenter.permissions[$0] == .authorized
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("WinterVoice")
                        .font(.largeTitle)
                    Text("Hold Right Option, speak, then release to insert text into the field that was focused when you began.")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                LabeledContent("Dictation status") {
                    Label(
                        dictationPresenter.statusTitle,
                        systemImage: dictationPresenter.state == .recording ? "waveform" : "circle.fill"
                    )
                    .foregroundStyle(dictationPresenter.state == .recording ? .red : .primary)
                }
                if let detail = dictationPresenter.statusDetail {
                    Text(detail)
                        .foregroundStyle(.secondary)
                }

                LabeledContent("Global hotkey") {
                    Label(
                        dictationPresenter.hotkeyHealth.title,
                        systemImage: dictationPresenter.hotkeyHealth == .listening
                            ? "keyboard.badge.ellipsis"
                            : "exclamationmark.triangle.fill"
                    )
                    .foregroundStyle(dictationPresenter.hotkeyHealth == .listening ? .green : .orange)
                }
                Text(dictationPresenter.hotkeyHealth.detail)
                    .foregroundStyle(.secondary)

                Divider()

                VStack(alignment: .leading, spacing: 10) {
                    Label("Private by design", systemImage: "lock.shield")
                        .font(.headline)
                    Text("Audio is sent only to Apple Speech on this Mac. WinterVoice has no network transcription fallback and does not save audio or transcripts.")
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 10) {
                    Label(
                        permissionsReady ? "Ready to dictate" : "Permissions need attention",
                        systemImage: permissionsReady ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
                    )
                    .font(.headline)
                    .foregroundStyle(permissionsReady ? .green : .orange)
                    Text(permissionsReady
                        ? "Microphone, Speech Recognition, Input Monitoring, and Accessibility access are allowed."
                        : "WinterVoice needs all four permissions for push-to-talk and safe insertion.")
                        .foregroundStyle(.secondary)
                    Button(permissionsReady ? "Review Permissions" : "Fix Permission Issues") {
                        presenter.navigate(to: .permissions)
                    }
                }
            }
            .frame(maxWidth: 680, alignment: .leading)
            .padding(32)
        }
        .navigationTitle("Overview")
    }
}

struct TranscriptionView: View {
    let capability: TranscriptionCapability

    var body: some View {
        Form {
            Section("Active Provider") {
                LabeledContent("Provider", value: capability.providerName)
                LabeledContent("Processing", value: capability.modeName)
                LabeledContent("Network fallback", value: "None")
            }

            Section("System Language") {
                LabeledContent("Locale") {
                    VStack(alignment: .trailing) {
                        Text(capability.localeDisplayName)
                        Text(capability.localeIdentifier)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                LabeledContent("Recognizer") {
                    Text(capability.isRecognizerAvailable ? "Available" : "Unavailable")
                }
                LabeledContent("On-device support") {
                    Text(capability.supportsOnDeviceRecognition ? "Supported" : "Not currently supported")
                }
            }

            Section {
                Text("Support depends on the current macOS language and downloaded system assets. WinterVoice checks again when recording begins and fails visibly if on-device recognition is unavailable; it never sends audio to a server.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Transcription")
    }
}

struct HotkeyView: View {
    @ObservedObject var presenter: DictationPresenter

    var body: some View {
        Form {
            Section("Push to Talk") {
                LabeledContent("Current hotkey") {
                    Text("Right Option")
                        .font(.body.monospaced())
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
                        .accessibilityLabel("Right Option key")
                }
                LabeledContent("Behavior", value: "Hold to record, release to transcribe")
                LabeledContent("Listener status") {
                    Text(presenter.hotkeyHealth.title)
                        .foregroundStyle(presenter.hotkeyHealth == .listening ? .green : .orange)
                }
                Text(presenter.hotkeyHealth.detail)
                    .foregroundStyle(.secondary)
            }

            Section {
                Text("The binding is fixed in this MVP. Left Option does not start dictation, and hotkey rebinding is not yet available.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Hotkey")
    }
}

struct PrivacyView: View {
    var body: some View {
        Form {
            Section("Audio and Transcripts") {
                privacyRow("Audio stays in the local Apple Speech pipeline.", icon: "waveform.badge.mic")
                privacyRow("No audio or transcription text is persisted or logged.", icon: "internaldrive")
                privacyRow("There is no network transcription path or fallback.", icon: "network.slash")
            }

            Section("Safe Insertion") {
                privacyRow("WinterVoice targets the exact field that was focused when dictation began.", icon: "scope")
                privacyRow("Direct Accessibility insertion is attempted before clipboard paste.", icon: "accessibility")
                privacyRow("Clipboard fallback restores prior contents and will not overwrite a newer clipboard change.", icon: "doc.on.clipboard")
                Text("If focus can no longer be verified, insertion fails safely instead of pasting into another field.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Privacy")
    }

    private func privacyRow(_ text: String, icon: String) -> some View {
        Label(text, systemImage: icon)
    }
}

struct PlannedFeatureView: View {
    let destination: AppShellDestination

    var body: some View {
        ContentUnavailableView {
            Label(destination.title, systemImage: destination.icon)
        } description: {
            VStack(spacing: 10) {
                Text("Planned")
                    .font(.caption.bold())
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(.quaternary, in: Capsule())
                Text(destination.plannedDescription)
            }
        }
        .navigationTitle(destination.title)
        .accessibilityLabel("\(destination.title). Planned and not available in this MVP.")
    }
}
