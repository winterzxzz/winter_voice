import AppKit
import Carbon.HIToolbox
import SwiftUI

struct OverviewView: View {
    @ObservedObject var presenter: AppShellPresenter
    @ObservedObject private var dictationPresenter: DictationPresenter

    init(presenter: AppShellPresenter) {
        self.presenter = presenter
        _dictationPresenter = ObservedObject(wrappedValue: presenter.dictationPresenter)
    }

    private var permissionsReady: Bool {
        OnboardingProgress(permissions: dictationPresenter.permissions) == .ready
    }
    private var providerStatus: ProviderStatus { presenter.providerStatus }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("WinterVoice")
                        .font(.largeTitle)
                    Text(providerStatus.overviewSummary)
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
                        dictationPresenter.hotkeyHealthTitle,
                        systemImage: dictationPresenter.hotkeyHealth == .listening
                            ? "keyboard.badge.ellipsis"
                            : "exclamationmark.triangle.fill"
                    )
                    .foregroundStyle(dictationPresenter.hotkeyHealth == .listening ? .green : .orange)
                }
                Text(dictationPresenter.hotkeyHealthDetail)
                    .foregroundStyle(.secondary)

                Divider()

                VStack(alignment: .leading, spacing: 10) {
                    Label("Private by design", systemImage: "lock.shield")
                        .font(.headline)
                    Text(providerStatus.privacySummary)
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 10) {
                    Label(
                        permissionsReady ? "Permissions ready" : "Permissions need attention",
                        systemImage: permissionsReady ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
                    )
                    .font(.headline)
                    .foregroundStyle(permissionsReady ? .green : .orange)
                    Text(permissionsReady
                        ? "Microphone, Input Monitoring, and Accessibility access are allowed. Provider: \(providerStatus.title) — \(providerStatus.stateLabel)."
                        : "WinterVoice needs all three permissions for audio capture, the global hotkey, and safe insertion.")
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
    @ObservedObject var presenter: AppShellPresenter
    @ObservedObject private var controller: TranscriptionSettingsController

    init(presenter: AppShellPresenter) {
        self.presenter = presenter
        _controller = ObservedObject(wrappedValue: presenter.transcriptionSettings)
    }

    private var status: ProviderStatus { presenter.providerStatus }
    private var configuration: ProviderConfigurationStore { presenter.providerConfiguration }
    private var models: ModelManager { presenter.modelManager }

    var body: some View {
        Form {
            Section("Transcription Provider") {
                Picker("Mode", selection: Binding(
                    get: { configuration.mode },
                    set: { configuration.mode = $0 }
                )) {
                    ForEach(ProviderMode.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                LabeledContent("Provider", value: status.title)
                LabeledContent("Status", value: status.stateLabel)
                Text(status.readiness.detail).foregroundStyle(.secondary)
            }

            switch configuration.mode {
            case .local:
                localSections
            case .remote:
                remoteSections
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Transcription")
        .onAppear { controller.loadRemoteDraft() }
    }

    @ViewBuilder
    private var localSections: some View {
        Section("Vietnamese and Multilingual") {
            ForEach(models.catalog.filter { !$0.isEnglishOnly }) { modelRow($0) }
        }
        Section("English Only") {
            ForEach(models.catalog.filter(\.isEnglishOnly)) { modelRow($0) }
        }
        if let error = models.lastError {
            Section { Text(error).foregroundStyle(.red) }
        }
        Section("Local Runtime Status") {
            Text("Selected models run privately on this Mac with whisper.cpp. Multilingual models automatically detect Vietnamese, English, and other supported languages.")
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var remoteSections: some View {
        Section("OpenAI-Compatible Endpoint") {
            TextField("Base URL", text: $controller.baseURL, prompt: Text("https://host.example/v1"))
            TextField("Model", text: $controller.remoteModel)
            TextField("Language (optional)", text: $controller.language)
            SecureField(
                configuration.hasAPIKey ? "API key (optional, saved in Keychain)" : "API key (optional)",
                text: $controller.apiKey
            )
        }
        Section {
            HStack {
                Button("Save Configuration") { controller.saveRemote() }.buttonStyle(.borderedProminent)
                Button("Test Connection") { controller.testRemoteConnection() }
                if configuration.hasAPIKey {
                    Button("Use Without Authentication", role: .destructive) { controller.removeAPIKey() }
                }
            }
            if let remoteResult = controller.remoteResult { Text(remoteResult).foregroundStyle(.secondary) }
        }
        Section {
            Text("HTTPS is required except for localhost or a private LAN endpoint. API keys are stored in Keychain. Test Connection probes the draft above without saving it.")
                .foregroundStyle(.secondary)
        }
    }

    private func modelRow(_ descriptor: ModelDescriptor) -> some View {
        let installed = models.installed.first { $0.id == descriptor.id }
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(descriptor.displayName)
                    Text("\(descriptor.languageLabel) · \(descriptor.formattedFileSize)")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if models.activeModelID == descriptor.id {
                    Text("Selected").foregroundStyle(.green)
                }
                if models.downloadingModelIDs.contains(descriptor.id)
                    || models.installingModelIDs.contains(descriptor.id) {
                    Button("Cancel") { models.cancelInstall(descriptor.id) }
                } else if installed != nil {
                    Button("Select") { Task { await models.select(descriptor.id) } }
                        .disabled(models.activeModelID == descriptor.id)
                    Button("Delete", role: .destructive) {
                        if let installed { Task { await models.delete(installed) } }
                    }
                } else {
                    Button("Download") { models.install(descriptor) }
                }
            }
            if let progress = models.downloadProgress[descriptor.id] {
                ProgressView(value: progress)
            } else if models.downloadingModelIDs.contains(descriptor.id) {
                ProgressView()
            } else if models.installingModelIDs.contains(descriptor.id) {
                ProgressView("Installing and verifying…")
            }
        }
    }

}

struct HotkeyView: View {
    @ObservedObject var presenter: DictationPresenter
    @ObservedObject var binding: HotkeyBindingStore
    var captureSuspender: HotkeyCaptureSuspending?

    var body: some View {
        Form {
            Section("Push to Talk") {
                LabeledContent("Current hotkey") {
                    HStack {
                        HotkeyRecorder(binding: $binding.selection, captureSuspender: captureSuspender)
                        Button("Reset to Fn / Globe") {
                            binding.selection = .function
                        }
                        .disabled(binding.selection == .function)
                    }
                }
                LabeledContent("Behavior", value: "Reserved for push to talk; provider required")
                LabeledContent("Listener status") {
                    Text(presenter.hotkeyHealthTitle)
                        .foregroundStyle(presenter.hotkeyHealth == .listening ? .green : .orange)
                }
                Text(presenter.hotkeyHealthDetail)
                    .foregroundStyle(.secondary)
            }

            Section {
                Text("Click Record Hotkey, then press a key, key combination, or hold multiple modifiers such as ⌥⇧ and release them together. Fn / Globe is the default. The change applies immediately and is saved for future launches.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Hotkey")
    }
}

private struct HotkeyRecorder: NSViewRepresentable {
    @Binding var binding: HotkeyBinding
    var captureSuspender: HotkeyCaptureSuspending?

    func makeNSView(context: Context) -> HotkeyRecorderView {
        let view = HotkeyRecorderView()
        view.onRecord = { self.binding = $0 }
        view.binding = binding
        view.captureSuspender = captureSuspender
        return view
    }

    func updateNSView(_ view: HotkeyRecorderView, context: Context) {
        view.onRecord = { self.binding = $0 }
        view.binding = binding
        view.captureSuspender = captureSuspender
    }
}

private final class HotkeyRecorderView: NSButton {
    var onRecord: ((HotkeyBinding) -> Void)?
    var binding: HotkeyBinding = .function { didSet { refreshTitle() } }
    weak var captureSuspender: (any HotkeyCaptureSuspending & AnyObject)?
    private var isRecording = false
    private var pendingModifierFlags: CGEventFlags = []

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        bezelStyle = .rounded
        target = self
        action = #selector(beginRecording)
        refreshTitle()
    }

    required init?(coder: NSCoder) { nil }

    override var acceptsFirstResponder: Bool { true }

    @objc private func beginRecording() {
        isRecording = true
        pendingModifierFlags = []
        // The global tap keeps matching the CURRENT binding while a new one is
        // recorded; pressing its modifier here must not start a dictation.
        captureSuspender?.suspendMatching()
        window?.makeFirstResponder(self)
        refreshTitle()
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil, isRecording { finishRecording() }
        super.viewWillMove(toWindow: newWindow)
    }

    override func keyDown(with event: NSEvent) {
        guard isRecording else { return super.keyDown(with: event) }
        if event.keyCode == UInt16(kVK_Escape) {
            finishRecording()
            return
        }
        onRecord?(.recorded(
            keyCode: Int64(event.keyCode),
            flags: event.modifierFlags.cgEventFlags
        ))
        finishRecording()
    }

    override func flagsChanged(with event: NSEvent) {
        guard isRecording else { return super.flagsChanged(with: event) }
        let active = event.modifierFlags.cgEventFlags.intersection(.hotkeyModifiers)
        if !active.isEmpty {
            pendingModifierFlags.formUnion(active)
            title = "\(HotkeyBinding.modifierChord(pendingModifierFlags).title)  ·  Release to save"
            return
        }
        guard !pendingModifierFlags.isEmpty else { return }
        onRecord?(.modifierChord(pendingModifierFlags))
        finishRecording()
    }

    override func resignFirstResponder() -> Bool {
        isRecording = false
        captureSuspender?.resumeMatching()
        refreshTitle()
        return super.resignFirstResponder()
    }

    private func finishRecording() {
        isRecording = false
        pendingModifierFlags = []
        captureSuspender?.resumeMatching()
        refreshTitle()
    }

    private func refreshTitle() {
        title = isRecording ? "Press hotkey…" : "\(binding.title)  ·  Record Hotkey"
    }
}

private extension NSEvent.ModifierFlags {
    var cgEventFlags: CGEventFlags {
        var result: CGEventFlags = []
        if contains(.command) { result.insert(.maskCommand) }
        if contains(.shift) { result.insert(.maskShift) }
        if contains(.option) { result.insert(.maskAlternate) }
        if contains(.control) { result.insert(.maskControl) }
        if contains(.function) { result.insert(.maskSecondaryFn) }
        return result
    }
}

struct PrivacyView: View {
    @ObservedObject var presenter: AppShellPresenter

    var body: some View {
        Form {
            Section("Audio and Transcripts") {
                privacyRow(presenter.providerStatus.privacySummary, icon: "waveform.badge.mic")
                privacyRow("Audio is held in memory only. Successfully inserted transcription text is saved locally in History; audio and API keys are never logged.", icon: "internaldrive")
                privacyRow("Local transcription runs on this Mac; Remote sends audio only to the endpoint you configure.", icon: "network.slash")
            }

            Section("Safe Insertion") {
                privacyRow("When the focused field is visible to Accessibility, WinterVoice targets that exact field and fails safely if it loses focus.", icon: "scope")
                privacyRow("Direct Accessibility insertion is attempted before clipboard paste.", icon: "accessibility")
                privacyRow("Apps that do not expose their focused field to Accessibility fall back to paste after verifying the same app is still frontmost — field-level verification is not possible there.", icon: "questionmark.app")
                privacyRow("Clipboard fallback marks the transcription as concealed and transient for clipboard managers, restores prior contents, and will not overwrite a newer clipboard change.", icon: "doc.on.clipboard")
                privacyRow("Text dictated into a detected password field is inserted but never saved to History.", icon: "key")
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Privacy")
    }

    private func privacyRow(_ text: String, icon: String) -> some View {
        Label(text, systemImage: icon)
    }
}
