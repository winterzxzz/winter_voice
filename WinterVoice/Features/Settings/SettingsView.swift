import AVFoundation
import ServiceManagement
import SwiftUI

// MARK: - In-app Settings page

/// The consolidated Settings screen of the reference app: Transcription,
/// Microphone, Behavior, Floating Widget, Permissions, and Privacy in one
/// scrollable page.
struct AppSettingsView: View {
    @ObservedObject var presenter: AppShellPresenter
    var reopenOnboarding: (() -> Void)?

    @ObservedObject private var controller: TranscriptionSettingsController
    @ObservedObject private var configuration: ProviderConfigurationStore
    @ObservedObject private var models: ModelManager
    @ObservedObject private var widgetPreferences: WidgetPreferences
    @StateObject private var launchAtLogin = LaunchAtLoginModel()
    @State private var activeMicrophoneName: String?

    init(presenter: AppShellPresenter, reopenOnboarding: (() -> Void)? = nil) {
        self.presenter = presenter
        self.reopenOnboarding = reopenOnboarding
        _controller = ObservedObject(wrappedValue: presenter.transcriptionSettings)
        _configuration = ObservedObject(wrappedValue: presenter.providerConfiguration)
        _models = ObservedObject(wrappedValue: presenter.modelManager)
        _widgetPreferences = ObservedObject(wrappedValue: presenter.widgetPreferences)
    }

    private var status: ProviderStatus { presenter.providerStatus }

    var body: some View {
        WVPage(
            icon: "gearshape",
            title: "Settings",
            subtitle: "Transcription, widget, and permissions."
        ) {
            transcriptionSection
            microphoneSection

            // fixedSize(vertical:) makes the row settle at the taller card's
            // height, then both cards stretch to fill it — equal heights.
            HStack(alignment: .top, spacing: Theme.Space.md) {
                behaviorSection
                widgetSection
            }
            .fixedSize(horizontal: false, vertical: true)

            permissionsSection
            privacySection
        }
        .onAppear {
            controller.loadRemoteDraft()
            refreshMicrophone()
            launchAtLogin.refresh()
        }
    }

    // MARK: Transcription

    private var transcriptionSection: some View {
        sectionCard("Transcription") {
            HStack(spacing: 12) {
                WVChipPicker(
                    selection: Binding(
                        get: { configuration.mode },
                        set: { configuration.mode = $0 }
                    ),
                    options: ProviderMode.allCases,
                    label: { $0 == .local ? "Local" : "Cloud" },
                    icon: { $0 == .local ? "cpu" : "cloud" }
                )
                Text(configuration.mode == .local
                    ? "Private and offline — audio never leaves your computer."
                    : "Audio is sent only to the endpoint you configure below.")
                    .font(.wvCaption)
                    .foregroundStyle(Theme.textSecondary)
                Spacer(minLength: 0)
                WVStatusPill(
                    text: status.stateLabel,
                    color: status.isReady ? Theme.success : Theme.warning,
                    filled: true
                )
            }

            if configuration.mode == .local {
                localModelRows
            } else {
                remoteRows
            }
        }
    }

    @ViewBuilder
    private var localModelRows: some View {
        if let active = activeModelName {
            Text("Using \(active) — pick a different one under All models.")
                .font(.wvCaption)
                .foregroundStyle(Theme.textSecondary)
        }
        if let error = models.lastError {
            Text(error).font(.wvCaption).foregroundStyle(Theme.danger)
        }
        WVDisclosureCard(label: "All models") {
            VStack(alignment: .leading, spacing: 14) {
                modelGroup("Vietnamese and Multilingual", models.catalog.filter { !$0.isEnglishOnly })
                modelGroup("English Only", models.catalog.filter(\.isEnglishOnly))
            }
        }
        WVDisclosureCard(label: storageSummary) {
            if models.installed.isEmpty {
                Text("No models downloaded yet. Download one under All models to dictate offline.")
                    .font(.wvCaption)
                    .foregroundStyle(Theme.textSecondary)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(models.installed.enumerated()), id: \.element.id) { index, installed in
                        if index > 0 { WVDivider().padding(.vertical, 8) }
                        HStack(spacing: Theme.Space.sm) {
                            WVIconBadge(systemImage: "internaldrive", size: 30)
                            Text(installed.displayName)
                                .font(.wvBody)
                                .foregroundStyle(Theme.textPrimary)
                            if models.activeModelID == installed.id {
                                WVStatusPill(text: "Selected", color: Theme.success, filled: true)
                            }
                            Spacer(minLength: Theme.Space.sm)
                            Text(formattedSize(for: installed.id))
                                .font(.wvCaption)
                                .foregroundStyle(Theme.textSecondary)
                            Button("Delete", role: .destructive) {
                                Task { await models.delete(installed) }
                            }
                            .buttonStyle(.wvGhost(role: .destructive))
                        }
                    }
                }
            }
        }
    }

    private var activeModelName: String? {
        guard let id = models.activeModelID else { return nil }
        return models.installed.first { $0.id == id }?.displayName
            ?? models.catalog.first { $0.id == id }?.displayName
    }

    private var storageSummary: String {
        let count = models.installed.count
        let bytes = models.installed.compactMap { installed in
            models.catalog.first { $0.id == installed.id }?.fileSize
        }.reduce(Int64(0), +)
        let size = ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
        let noun = count == 1 ? "model" : "models"
        return count == 0
            ? "Local model storage — no models on disk"
            : "Local model storage — \(count) \(noun), \(size) on disk"
    }

    private func formattedSize(for id: String) -> String {
        guard let descriptor = models.catalog.first(where: { $0.id == id }) else { return "" }
        return descriptor.formattedFileSize
    }

    @ViewBuilder
    private func modelGroup(_ title: String, _ descriptors: [ModelDescriptor]) -> some View {
        if !descriptors.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text(title.uppercased())
                    .font(.system(size: 10.5, weight: .semibold))
                    .tracking(0.6)
                    .foregroundStyle(Theme.textTertiary)
                VStack(spacing: 0) {
                    ForEach(Array(descriptors.enumerated()), id: \.element.id) { index, descriptor in
                        if index > 0 { WVDivider() }
                        modelRow(descriptor).padding(.vertical, 10)
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
                            tint: isActive ? Theme.success : Theme.textSecondary,
                            size: 30)
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
    private var remoteRows: some View {
        VStack(alignment: .leading, spacing: 12) {
            WVField(label: "Base URL") {
                TextField("", text: $controller.baseURL, prompt: Text("https://host.example/v1"))
                    .textFieldStyle(.wv)
            }
            HStack(alignment: .top, spacing: 10) {
                WVField(label: "Model") {
                    TextField("", text: $controller.remoteModel).textFieldStyle(.wv)
                }
                WVField(label: "Language (optional)") {
                    TextField("", text: $controller.language).textFieldStyle(.wv)
                }
            }
            WVField(label: configuration.hasAPIKey ? "API key (saved in Keychain)" : "API key (optional)") {
                SecureField("", text: $controller.apiKey).textFieldStyle(.wv)
            }
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
            Text("HTTPS is required except for localhost or a private LAN endpoint. API keys are stored in Keychain. Test Connection probes the draft above without saving it.")
                .font(.wvCaption)
                .foregroundStyle(Theme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Microphone

    private var microphoneSection: some View {
        sectionCard("Microphone") {
            HStack(spacing: 10) {
                Text("System Default")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(
                        Theme.inset,
                        in: RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                            .strokeBorder(Theme.border, lineWidth: 1)
                    )
                if let activeMicrophoneName {
                    WVStatusPill(text: "Active: \(activeMicrophoneName)", color: Theme.success)
                } else {
                    Text("No input device detected")
                        .font(.wvCaption)
                        .foregroundStyle(Theme.warning)
                }
                Spacer(minLength: 0)
                Button { refreshMicrophone() } label: {
                    Label("Refresh", systemImage: "arrow.triangle.2.circlepath")
                }
                .buttonStyle(.wvGhost)
            }
            Text("WinterVoice records from the input device selected in macOS Sound settings.")
                .font(.wvCaption)
                .foregroundStyle(Theme.textTertiary)
        }
    }

    private func refreshMicrophone() {
        activeMicrophoneName = AVCaptureDevice.default(for: .audio)?.localizedName
    }

    // MARK: Behavior

    private var behaviorSection: some View {
        sectionCard("Behavior") {
            HStack(alignment: .top, spacing: Theme.Space.sm) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Launch at login")
                        .font(.wvRowTitle)
                        .foregroundStyle(Theme.textPrimary)
                    Text("Start WinterVoice automatically when you log in, ready in the menu bar.")
                        .font(.wvCaption)
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: Theme.Space.sm)
                Toggle("", isOn: $launchAtLogin.isEnabled)
                    .toggleStyle(.wv)
                    .labelsHidden()
            }
            if let error = launchAtLogin.lastError {
                Text(error).font(.wvCaption).foregroundStyle(Theme.danger)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    // MARK: Floating widget

    private var widgetSection: some View {
        sectionCard("Floating Widget") {
            VStack(alignment: .leading, spacing: 2) {
                Text("Show widget")
                    .font(.wvRowTitle)
                    .foregroundStyle(Theme.textPrimary)
                Text("The pill that shows recording status.")
                    .font(.wvCaption)
                    .foregroundStyle(Theme.textSecondary)
            }
            WVChipPicker(
                selection: $widgetPreferences.visibility,
                options: WidgetVisibility.allCases,
                label: { $0.title }
            )
            Text("Drag the pill to move it. Press Cmd + Shift + Space to bring it to the front.")
                .font(.wvCaption)
                .foregroundStyle(Theme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    // MARK: Permissions

    private var permissionsSection: some View {
        sectionCard(
            "Permissions",
            subtitle: "Microphone, Input Monitoring, and Accessibility are required for audio capture, the global hotkey, and safe insertion."
        ) {
            PermissionsView(
                presenter: presenter.dictationPresenter,
                showsIntroduction: false,
                reopenOnboarding: reopenOnboarding
            )
        }
    }

    // MARK: Privacy

    private var privacySection: some View {
        sectionCard("Privacy") {
            HStack(alignment: .top, spacing: Theme.Space.sm) {
                WVIconBadge(systemImage: "lock.shield", tint: Theme.success, size: 30)
                VStack(alignment: .leading, spacing: 6) {
                    Text(status.privacySummary)
                        .font(.wvBody)
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Audio is held in memory only. Inserted text is saved locally in History; audio and API keys are never logged. Text dictated into a detected password field is never saved.")
                        .font(.wvCaption)
                        .foregroundStyle(Theme.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
        }
    }

    // MARK: Section scaffold

    private func sectionCard(
        _ title: String,
        subtitle: String? = nil,
        @ViewBuilder content: () -> some View
    ) -> some View {
        WVCard {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.wvHeadline)
                        .foregroundStyle(Theme.textPrimary)
                    if let subtitle {
                        Text(subtitle)
                            .font(.wvCaption)
                            .foregroundStyle(Theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                content()
            }
            // Fills the height a side-by-side row proposes so paired cards
            // match; inert in a plain vertical flow.
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }
}

// MARK: - Launch at login

/// Bridges the "Launch at login" toggle to `SMAppService.mainApp`.
@MainActor
final class LaunchAtLoginModel: ObservableObject {
    @Published var isEnabled: Bool {
        didSet {
            guard !suppressApply, oldValue != isEnabled else { return }
            apply()
        }
    }
    @Published private(set) var lastError: String?

    private var suppressApply = false

    init() {
        isEnabled = SMAppService.mainApp.status == .enabled
    }

    func refresh() {
        suppressApply = true
        isEnabled = SMAppService.mainApp.status == .enabled
        suppressApply = false
    }

    private func apply() {
        do {
            if isEnabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            lastError = nil
        } catch {
            lastError = "Could not update the login item: \(error.localizedDescription)"
            suppressApply = true
            isEnabled = SMAppService.mainApp.status == .enabled
            suppressApply = false
        }
    }
}

// MARK: - Settings scene (Cmd+, window)

struct SettingsView: View {
    @ObservedObject var presenter: DictationPresenter

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("WinterVoice")
                        .font(.wvTitle)
                        .foregroundStyle(Theme.textPrimary)
                    Text("Configure permissions here. Transcription, shortcuts, and the widget are managed in the main WinterVoice window.")
                        .font(.wvBody)
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                PermissionsView(presenter: presenter, showsIntroduction: false)
            }
            .padding(24)
        }
        .frame(width: 620, height: 470)
        .background(Theme.canvas)
        .tint(Theme.accent)
        .preferredColorScheme(.dark)
        .onAppear { presenter.refreshPermissions() }
    }
}
