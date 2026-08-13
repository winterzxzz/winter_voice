import AppKit
import Carbon.HIToolbox
import SwiftUI

// MARK: - Home

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
    private var isRecording: Bool { dictationPresenter.state == .recording }
    private var listening: Bool { dictationPresenter.hotkeyHealth == .listening }

    var body: some View {
        WVPage(icon: "house", title: "Home", subtitle: providerStatus.overviewSummary) {
            WVCard {
                VStack(spacing: 0) {
                    WVRow(
                        icon: isRecording ? "waveform" : "mic",
                        title: "Dictation",
                        subtitle: dictationPresenter.statusDetail ?? "Hold your hotkey to dictate into any app."
                    ) {
                        WVStatusPill(
                            text: dictationPresenter.statusTitle,
                            color: isRecording ? Theme.danger : Theme.success,
                            filled: true
                        )
                    }
                    WVDivider().padding(.vertical, 12)
                    WVRow(
                        icon: listening ? "keyboard" : "exclamationmark.triangle.fill",
                        title: "Global hotkey",
                        subtitle: dictationPresenter.hotkeyHealthDetail
                    ) {
                        WVStatusPill(
                            text: dictationPresenter.hotkeyHealthTitle,
                            color: listening ? Theme.success : Theme.warning,
                            filled: true
                        )
                    }
                }
            }

            WVCard {
                HStack(alignment: .top, spacing: Theme.Space.sm) {
                    WVIconBadge(systemImage: "lock.shield", tint: Theme.success)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Private by design")
                            .font(.wvHeadline)
                            .foregroundStyle(Theme.textPrimary)
                        Text(providerStatus.privacySummary)
                            .font(.wvBody)
                            .foregroundStyle(Theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            WVCard {
                HStack(alignment: .top, spacing: Theme.Space.sm) {
                    WVIconBadge(
                        systemImage: permissionsReady ? "checkmark.circle.fill" : "exclamationmark.triangle.fill",
                        tint: permissionsReady ? Theme.success : Theme.warning
                    )
                    VStack(alignment: .leading, spacing: 6) {
                        Text(permissionsReady ? "Permissions ready" : "Permissions need attention")
                            .font(.wvHeadline)
                            .foregroundStyle(permissionsReady ? Theme.success : Theme.warning)
                        Text(permissionsReady
                            ? "Microphone, Input Monitoring, and Accessibility access are allowed. Provider: \(providerStatus.title) — \(providerStatus.stateLabel)."
                            : "WinterVoice needs all three permissions for audio capture, the global hotkey, and safe insertion.")
                            .font(.wvBody)
                            .foregroundStyle(Theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Group {
                            if permissionsReady {
                                Button("Review Permissions") { presenter.navigate(to: .permissions) }
                                    .buttonStyle(.wvSecondary)
                            } else {
                                Button("Fix Permission Issues") { presenter.navigate(to: .permissions) }
                                    .buttonStyle(.wvPrimary)
                            }
                        }
                        .padding(.top, 2)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }
}

// MARK: - Transcription

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
        WVPage(icon: "waveform", title: "Transcription", subtitle: "Choose where your speech is turned into text.") {
            WVCard {
                VStack(alignment: .leading, spacing: 14) {
                    Picker("", selection: Binding(
                        get: { configuration.mode },
                        set: { configuration.mode = $0 }
                    )) {
                        ForEach(ProviderMode.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()

                    WVDivider()
                    infoLine("Provider", status.title)
                    infoLine("Status", status.stateLabel)
                    Text(status.readiness.detail)
                        .font(.wvCaption)
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            switch configuration.mode {
            case .local:
                localSections
            case .remote:
                remoteSections
            }
        }
        .onAppear { controller.loadRemoteDraft() }
    }

    private func infoLine(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(.wvBody).foregroundStyle(Theme.textSecondary)
            Spacer()
            Text(value).font(.wvBody.weight(.medium)).foregroundStyle(Theme.textPrimary)
        }
    }

    @ViewBuilder
    private var localSections: some View {
        modelGroup("Vietnamese and Multilingual", models.catalog.filter { !$0.isEnglishOnly })
        modelGroup("English Only", models.catalog.filter(\.isEnglishOnly))
        if let error = models.lastError {
            WVCard { Text(error).font(.wvBody).foregroundStyle(Theme.danger) }
        }
        WVCard {
            Text("Selected models run privately on this Mac with whisper.cpp. Multilingual models automatically detect Vietnamese, English, and other supported languages.")
                .font(.wvCaption)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private func modelGroup(_ title: String, _ descriptors: [ModelDescriptor]) -> some View {
        if !descriptors.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text(title.uppercased())
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(0.6)
                    .foregroundStyle(Theme.textTertiary)
                WVCard(padding: 6) {
                    VStack(spacing: 0) {
                        ForEach(Array(descriptors.enumerated()), id: \.element.id) { index, descriptor in
                            if index > 0 { WVDivider().padding(.horizontal, 10) }
                            modelRow(descriptor).padding(10)
                        }
                    }
                }
            }
        }
    }

    private func modelRow(_ descriptor: ModelDescriptor) -> some View {
        let installed = models.installed.first { $0.id == descriptor.id }
        let isActive = models.activeModelID == descriptor.id
        let busy = models.downloadingModelIDs.contains(descriptor.id)
            || models.installingModelIDs.contains(descriptor.id)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: Theme.Space.sm) {
                WVIconBadge(systemImage: isActive ? "checkmark.circle.fill" : "cube.box",
                            tint: isActive ? Theme.success : Theme.textSecondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(descriptor.displayName)
                        .font(.wvRowTitle)
                        .foregroundStyle(Theme.textPrimary)
                    Text("\(descriptor.languageLabel) · \(descriptor.formattedFileSize)")
                        .font(.wvCaption)
                        .foregroundStyle(Theme.textSecondary)
                }
                Spacer(minLength: Theme.Space.sm)
                if isActive { WVStatusPill(text: "Selected", color: Theme.success, filled: true) }
                if busy {
                    Button("Cancel") { models.cancelInstall(descriptor.id) }
                        .buttonStyle(.wvGhost(role: .destructive))
                } else if installed != nil {
                    Button("Select") { Task { await models.select(descriptor.id) } }
                        .buttonStyle(.wvSecondary)
                        .disabled(isActive)
                    Button("Delete", role: .destructive) {
                        if let installed { Task { await models.delete(installed) } }
                    }
                    .buttonStyle(.wvGhost(role: .destructive))
                } else {
                    Button("Download") { models.install(descriptor) }
                        .buttonStyle(.wvPrimary)
                }
            }
            if let progress = models.downloadProgress[descriptor.id] {
                ProgressView(value: progress).tint(Theme.accent)
            } else if models.downloadingModelIDs.contains(descriptor.id) {
                ProgressView().controlSize(.small)
            } else if models.installingModelIDs.contains(descriptor.id) {
                ProgressView("Installing and verifying…").controlSize(.small)
            }
        }
    }

    @ViewBuilder
    private var remoteSections: some View {
        WVCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("OpenAI-Compatible Endpoint")
                    .font(.wvHeadline)
                    .foregroundStyle(Theme.textPrimary)
                WVField(label: "Base URL") {
                    TextField("", text: $controller.baseURL, prompt: Text("https://host.example/v1"))
                        .textFieldStyle(.wv)
                }
                WVField(label: "Model") {
                    TextField("", text: $controller.remoteModel).textFieldStyle(.wv)
                }
                WVField(label: "Language (optional)") {
                    TextField("", text: $controller.language).textFieldStyle(.wv)
                }
                WVField(label: configuration.hasAPIKey ? "API key (saved in Keychain)" : "API key (optional)") {
                    SecureField("", text: $controller.apiKey).textFieldStyle(.wv)
                }
            }
        }
        WVCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Button("Save Configuration") { controller.saveRemote() }.buttonStyle(.wvPrimary)
                    Button("Test Connection") { controller.testRemoteConnection() }.buttonStyle(.wvSecondary)
                    if configuration.hasAPIKey {
                        Button("Use Without Authentication", role: .destructive) { controller.removeAPIKey() }
                            .buttonStyle(.wvGhost(role: .destructive))
                    }
                }
                if let remoteResult = controller.remoteResult {
                    Text(remoteResult).font(.wvCaption).foregroundStyle(Theme.textSecondary)
                }
            }
        }
        WVCard {
            Text("HTTPS is required except for localhost or a private LAN endpoint. API keys are stored in Keychain. Test Connection probes the draft above without saving it.")
                .font(.wvCaption)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Shortcuts

struct HotkeyView: View {
    @ObservedObject var presenter: DictationPresenter
    @ObservedObject var binding: HotkeyBindingStore
    var captureSuspender: HotkeyCaptureSuspending?

    private var listening: Bool { presenter.hotkeyHealth == .listening }

    var body: some View {
        WVPage(icon: "keyboard", title: "Shortcuts", subtitle: "Set the keys that control recording.") {
            WVCard {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: Theme.Space.sm) {
                        WVIconBadge(systemImage: "mic")
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Push to Talk")
                                .font(.wvRowTitle)
                                .foregroundStyle(Theme.textPrimary)
                            Text("Hold to record. Release to insert your words.")
                                .font(.wvCaption)
                                .foregroundStyle(Theme.textSecondary)
                        }
                        Spacer(minLength: Theme.Space.sm)
                        HotkeyRecorder(binding: $binding.selection, captureSuspender: captureSuspender)
                            .frame(width: 210, height: 30)
                        Button("Reset") { binding.selection = .function }
                            .buttonStyle(.wvGhost)
                            .disabled(binding.selection == .function)
                    }

                    WVDivider()

                    HStack {
                        Text("Recording mode")
                            .font(.wvBody)
                            .foregroundStyle(Theme.textSecondary)
                        Spacer()
                        Picker("", selection: $binding.recordingMode) {
                            ForEach(RecordingMode.allCases, id: \.self) { Text($0.title).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .frame(width: 240)
                    }
                    Text(binding.recordingMode.instruction(binding: binding.selection))
                        .font(.wvCaption)
                        .foregroundStyle(Theme.textSecondary)

                    WVDivider()

                    HStack {
                        Text("Listener status")
                            .font(.wvBody)
                            .foregroundStyle(Theme.textSecondary)
                        Spacer()
                        WVStatusPill(
                            text: presenter.hotkeyHealthTitle,
                            color: listening ? Theme.success : Theme.warning,
                            filled: true
                        )
                    }
                    Text(presenter.hotkeyHealthDetail)
                        .font(.wvCaption)
                        .foregroundStyle(Theme.textSecondary)
                }
            }

            WVCard {
                Text("Click Record Hotkey, then press a key, key combination, or hold multiple modifiers such as ⌥⇧ and release them together. Fn / Globe is the default. Hold to Talk records while the key is held; Toggle starts on one press and stops on the next. Changes apply immediately and are saved for future launches.")
                    .font(.wvCaption)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// MARK: - Privacy

struct PrivacyView: View {
    @ObservedObject var presenter: AppShellPresenter

    var body: some View {
        WVPage(icon: "hand.raised", title: "Privacy", subtitle: "How WinterVoice handles your audio and text.") {
            card("Audio and Transcripts", rows: [
                (presenter.providerStatus.privacySummary, "waveform.badge.mic"),
                ("Audio is held in memory only. Successfully inserted transcription text is saved locally in History; audio and API keys are never logged.", "internaldrive"),
                ("Local transcription runs on this Mac; Remote sends audio only to the endpoint you configure.", "network.slash"),
            ])
            card("Safe Insertion", rows: [
                ("When the focused field is visible to Accessibility, WinterVoice targets that exact field and fails safely if it loses focus.", "scope"),
                ("Direct Accessibility insertion is attempted before clipboard paste.", "accessibility"),
                ("Apps that do not expose their focused field to Accessibility fall back to paste after verifying the same app is still frontmost — field-level verification is not possible there.", "questionmark.app"),
                ("Clipboard fallback marks the transcription as concealed and transient for clipboard managers, restores prior contents, and will not overwrite a newer clipboard change.", "doc.on.clipboard"),
                ("Text dictated into a detected password field is inserted but never saved to History.", "key"),
            ])
        }
    }

    private func card(_ title: String, rows: [(String, String)]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(Theme.textTertiary)
            WVCard {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                        if index > 0 { WVDivider().padding(.vertical, 11) }
                        HStack(alignment: .top, spacing: Theme.Space.sm) {
                            WVIconBadge(systemImage: row.1, size: 30)
                            Text(row.0)
                                .font(.wvBody)
                                .foregroundStyle(Theme.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 0)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Hotkey recorder (AppKit)

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
