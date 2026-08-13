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
        AppPermission.allCases.allSatisfy {
            dictationPresenter.permissions[$0] == .authorized
        }
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

    private var status: ProviderStatus { presenter.providerStatus }

    var body: some View {
        Form {
            Section("Active Provider") {
                Picker("Mode", selection: Binding(
                    get: { presenter.providerConfiguration.mode },
                    set: { presenter.providerConfiguration.mode = $0 }
                )) {
                    ForEach(ProviderMode.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                LabeledContent("Provider", value: status.title)
                LabeledContent("Status", value: status.stateLabel)
            }

            Section {
                Text(status.readiness.detail)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Transcription")
    }
}

struct ModelsView: View {
    @ObservedObject var manager: ModelManager

    var body: some View {
        Form {
            Section("Downloadable Models") {
                if manager.catalog.isEmpty {
                    ContentUnavailableView(
                        "No Published Models",
                        systemImage: "shippingbox",
                        description: Text(manager.catalogMessage)
                    )
                }
                ForEach(manager.catalog) { descriptor in
                    VStack(alignment: .leading) {
                        HStack {
                            Text(descriptor.displayName)
                            Spacer()
                            if manager.downloadingModelIDs.contains(descriptor.id)
                                || manager.installingModelIDs.contains(descriptor.id) {
                                Button("Cancel") { manager.cancelInstall(descriptor.id) }
                            } else {
                                Button("Download") { manager.install(descriptor) }
                            }
                        }
                        if let progress = manager.downloadProgress[descriptor.id] {
                            ProgressView(value: progress)
                        } else if manager.downloadingModelIDs.contains(descriptor.id) {
                            ProgressView()
                        } else if manager.installingModelIDs.contains(descriptor.id) {
                            ProgressView("Installing and verifying…")
                        }
                    }
                }
                if let error = manager.lastError { Text(error).foregroundStyle(.red) }
            }
            Section("Installed Models") {
                if manager.installed.isEmpty {
                    Text("No local models are installed.").foregroundStyle(.secondary)
                }
                ForEach(manager.installed) { model in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(model.displayName)
                            Text(model.runtime).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if manager.activeModelID == model.id { Text("Active").foregroundStyle(.green) }
                        Button("Select") { Task { try? await manager.select(model.id) } }
                        Button("Delete", role: .destructive) { Task { try? await manager.delete(model) } }
                    }
                }
            }
            Section {
                Text("A real local catalog requires an owner-approved model artifact, authoritative download URL, SHA-256, and suitable license. WinterVoice does not expose a fake download.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Models")
    }
}

struct RemoteProvidersView: View {
    @ObservedObject var store: ProviderConfigurationStore
    @State private var baseURL = ""
    @State private var model = ""
    @State private var language = ""
    @State private var apiKey = ""
    @State private var result: String?

    var body: some View {
        Form {
            Section("OpenAI-Compatible Endpoint") {
                TextField("Base URL", text: $baseURL, prompt: Text("https://host.example/v1"))
                TextField("Model", text: $model)
                TextField("Language (optional)", text: $language)
                SecureField(store.hasAPIKey ? "API key (optional, saved in Keychain)" : "API key (optional)", text: $apiKey)
            }
            Section {
                HStack {
                    Button("Save Configuration") { save() }
                        .buttonStyle(.borderedProminent)
                    Button("Test Connection") { testConnection() }
                    if store.hasAPIKey {
                        Button("Use Without Authentication", role: .destructive) { removeAPIKey() }
                    }
                }
                if let result { Text(result).foregroundStyle(.secondary) }
            }
            Section {
                Text("HTTPS is required except for an explicitly entered localhost or private LAN HTTP endpoint. Authentication is optional; when supplied, the API key is stored only in macOS Keychain and sent as Bearer authentication. WinterVoice does not log keys or transcript text.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Remote Providers")
        .onAppear {
            baseURL = store.remote.baseURL
            model = store.remote.model
            language = store.remote.language
        }
    }

    private var draft: RemoteProviderConfiguration {
        .init(baseURL: baseURL, model: model, language: language)
    }

    private func save() {
        do {
            _ = try RemoteTranscriptionProvider.endpoint(for: draft)
            guard !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw DictationFailure(message: "Enter a model name.", recovery: "")
            }
            try store.saveRemote(draft, apiKey: apiKey.isEmpty ? nil : apiKey)
            apiKey = ""
            result = "Configuration saved."
        } catch let failure as DictationFailure { result = failure.message }
        catch { result = "Could not save the configuration." }
    }

    private func testConnection() {
        do {
            _ = try RemoteTranscriptionProvider.endpoint(for: draft)
            guard !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return result = "Enter a model name."
            }
            try store.saveRemote(draft, apiKey: apiKey.isEmpty ? nil : apiKey)
            apiKey = ""
            result = "Testing connection…"
            Task {
                do {
                    let key = try store.apiKey()
                    _ = try await RemoteTranscriptionProvider().transcribe(
                        audio: RecordedAudio(samples: [0], sampleRate: 16_000),
                        configuration: store.remote,
                        apiKey: key
                    )
                    result = "Connected successfully."
                } catch let failure as DictationFailure { result = failure.message }
                catch { result = "Connection test failed." }
            }
        } catch let failure as DictationFailure { result = failure.message }
        catch { result = "Configuration is invalid." }
    }

    private func removeAPIKey() {
        do {
            try store.removeAPIKey()
            apiKey = ""
            result = "API key removed. Remote requests will use no authentication."
        } catch let failure as DictationFailure { result = failure.message }
        catch { result = "Could not remove the API key." }
    }
}

struct HotkeyView: View {
    @ObservedObject var presenter: DictationPresenter
    @ObservedObject var binding: HotkeyBindingStore

    var body: some View {
        Form {
            Section("Push to Talk") {
                LabeledContent("Current hotkey") {
                    HStack {
                        HotkeyRecorder(binding: $binding.selection)
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

    func makeNSView(context: Context) -> HotkeyRecorderView {
        let view = HotkeyRecorderView()
        view.onRecord = { self.binding = $0 }
        view.binding = binding
        return view
    }

    func updateNSView(_ view: HotkeyRecorderView, context: Context) {
        view.onRecord = { self.binding = $0 }
        view.binding = binding
    }
}

private final class HotkeyRecorderView: NSButton {
    var onRecord: ((HotkeyBinding) -> Void)?
    var binding: HotkeyBinding = .function { didSet { refreshTitle() } }
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
        window?.makeFirstResponder(self)
        refreshTitle()
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
        refreshTitle()
        return super.resignFirstResponder()
    }

    private func finishRecording() {
        isRecording = false
        pendingModifierFlags = []
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
                privacyRow("Local models remain blocked on an approved artifact and runtime; generic Remote is operational when configured.", icon: "network.slash")
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
