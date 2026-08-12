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
                LabeledContent("Behavior", value: "Reserved for push to talk; provider required")
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
    @ObservedObject var presenter: AppShellPresenter

    var body: some View {
        Form {
            Section("Audio and Transcripts") {
                privacyRow(presenter.providerStatus.privacySummary, icon: "waveform.badge.mic")
                privacyRow("No audio or transcription text is persisted or logged.", icon: "internaldrive")
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
