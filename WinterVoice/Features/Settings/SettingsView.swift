import AppKit
import AVFoundation
import ServiceManagement
import SwiftUI
import UniformTypeIdentifiers

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
    @ObservedObject private var theme = ThemeStore.shared
    @ObservedObject private var microphone: MicrophonePreferences
    @ObservedObject private var behavior: BehaviorPreferences
    @ObservedObject private var updates: UpdateController
    /// A preset chip the user tapped whose model is still downloading; selected
    /// automatically once the install lands.
    @State private var pendingPresetModelID: String?
    @State private var isImportingModel = false

    init(presenter: AppShellPresenter, reopenOnboarding: (() -> Void)? = nil) {
        self.presenter = presenter
        self.reopenOnboarding = reopenOnboarding
        _controller = ObservedObject(wrappedValue: presenter.transcriptionSettings)
        _configuration = ObservedObject(wrappedValue: presenter.providerConfiguration)
        _models = ObservedObject(wrappedValue: presenter.modelManager)
        _widgetPreferences = ObservedObject(wrappedValue: presenter.widgetPreferences)
        _microphone = ObservedObject(wrappedValue: presenter.microphonePreferences)
        _behavior = ObservedObject(wrappedValue: presenter.behaviorPreferences)
        _updates = ObservedObject(wrappedValue: presenter.updates)
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
            behaviorSection
            widgetSection
            themeSection
            updatesSection
            permissionsSection
        }
        .onAppear {
            controller.loadRemoteDraft()
            refreshMicrophone()
            launchAtLogin.refresh()
        }
        .onChange(of: models.installed) { _, installed in
            guard let id = pendingPresetModelID,
                  installed.contains(where: { $0.id == id }) else { return }
            pendingPresetModelID = nil
            Task { await models.select(id) }
        }
        .onChange(of: models.downloadingModelIDs) { _, downloading in
            // A cancelled or failed preset download must not auto-select later.
            guard let id = pendingPresetModelID,
                  !downloading.contains(id),
                  !models.installingModelIDs.contains(id),
                  !models.installed.contains(where: { $0.id == id }) else { return }
            pendingPresetModelID = nil
        }
    }

    // MARK: Transcription

    private var transcriptionSection: some View {
        sectionCard("Transcription", trailing: {
            WVStatusPill(
                text: status.stateLabel,
                color: status.isReady ? Theme.success : Theme.warning,
                filled: true
            )
        }) {
            HStack(spacing: 12) {
                WVChipPicker(
                    selection: Binding(
                        get: { configuration.mode },
                        set: { configuration.mode = $0 }
                    ),
                    options: ProviderMode.allCases,
                    label: { $0 == .local ? "Local" : "Cloud" },
                    icon: { $0 == .local ? "cpu" : "cloud" },
                    grouped: true
                )
                Text(configuration.mode == .local
                    ? "Private and offline — audio never leaves your computer."
                    : "Audio is sent only to the endpoint you configure below.")
                    .font(.wvCaption)
                    .foregroundStyle(Theme.textSecondary)
                Spacer(minLength: 0)
            }

            languageRow

            if configuration.mode == .local {
                localModelRows
            } else {
                remoteRows
            }
        }
    }

    // MARK: Language

    /// The reference Language dropdown: one selection drives both local
    /// whisper and the cloud `language` field. Auto-detect is the default.
    private var languageRow: some View {
        HStack(spacing: 12) {
            Text("Language")
                .font(.wv(13))
                .foregroundStyle(Theme.textPrimary)
            languageMenu
            Text(languageCaption)
                .font(.wvCaption)
                .foregroundStyle(Theme.textSecondary)
            Spacer(minLength: 0)
        }
    }

    private var languageCaption: String {
        if configuration.mode == .local, models.activeModel?.isEnglishOnly == true {
            return "The selected model is English-only, so it always transcribes English."
        }
        return configuration.languageCode == nil
            ? "Auto-detect finds the spoken language for you."
            : "Applies to both local and cloud transcription."
    }

    private var languageMenu: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
        let selectedName = TranscriptionLanguage.name(forCode: configuration.languageCode) ?? "Auto-detect"
        return Menu {
            Toggle("Auto-detect", isOn: Binding(
                get: { configuration.languageCode == nil },
                set: { _ in configuration.languageCode = nil }
            ))
            Divider()
            ForEach(TranscriptionLanguage.all) { language in
                Toggle(language.name, isOn: Binding(
                    get: { configuration.languageCode == language.code },
                    set: { _ in configuration.languageCode = language.code }
                ))
            }
        } label: {
            HStack(spacing: 10) {
                Text(selectedName)
                    .font(.wv(13, .medium))
                    .foregroundStyle(Theme.textPrimary)
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Theme.textTertiary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Theme.inset, in: shape)
            .overlay(shape.strokeBorder(Theme.border, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
    }

    @ViewBuilder
    private var localModelRows: some View {
        HStack(spacing: 12) {
            WVChipPicker(
                selection: Binding(
                    get: { activePreset },
                    set: { applyPreset($0) }
                ),
                options: ModelPreset.allCases,
                label: { $0.title }
            )
            if let id = pendingPresetModelID,
               models.downloadingModelIDs.contains(id) || models.installingModelIDs.contains(id) {
                ProgressView(value: models.downloadProgress[id])
                    .progressViewStyle(.linear)
                    .tint(Theme.accent)
                    .frame(width: 72)
            }
            Text(presetCaption)
                .font(.wvCaption)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        if let error = models.lastError {
            Text(error).font(.wvCaption).foregroundStyle(Theme.danger)
        }
        WVDisclosureCard(label: "All models") {
            VStack(alignment: .leading, spacing: 14) {
                VStack(spacing: 0) {
                    ForEach(Array(models.catalog.enumerated()), id: \.element.id) { index, descriptor in
                        if index > 0 { WVDivider() }
                        modelRow(descriptor).padding(.vertical, 10)
                    }
                }
                WVDivider()
                HStack(spacing: Theme.Space.sm) {
                    Button("Import Model…") { isImportingModel = true }
                        .buttonStyle(.wvSecondary)
                    Text("Bring any ggml whisper .bin — medium, large-v3, quantized builds…")
                        .font(.wvCaption)
                        .foregroundStyle(Theme.textSecondary)
                    Spacer(minLength: 0)
                }
                .fileImporter(
                    isPresented: $isImportingModel,
                    allowedContentTypes: [UTType(filenameExtension: "bin") ?? .data]
                ) { result in
                    if case .success(let url) = result {
                        Task { await models.importModel(from: url) }
                    }
                }
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
                            if models.activeModelID != installed.id {
                                Button("Select") {
                                    Task { await models.select(installed.id) }
                                }
                                .buttonStyle(.wvSecondary)
                            }
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

    // MARK: Model presets

    /// The reference quality chips. Each named preset maps to a catalog
    /// whisper.cpp model; `custom` lights up when the active model came from
    /// elsewhere (e.g. an imported ggml file).
    private enum ModelPreset: CaseIterable, Hashable {
        case fast, balanced, accurate, custom

        var title: String {
            switch self {
            case .fast: "Fast"
            case .balanced: "Balanced"
            case .accurate: "Accurate"
            case .custom: "Custom"
            }
        }

        var modelID: String? {
            switch self {
            case .fast: "whisper-tiny-en"
            case .balanced: "whisper-base-en"
            case .accurate: "whisper-small-en"
            case .custom: nil
            }
        }
    }

    private var activePreset: ModelPreset {
        ModelPreset.allCases.first {
            $0.modelID != nil && $0.modelID == models.activeModelID
        } ?? .custom
    }

    private func applyPreset(_ preset: ModelPreset) {
        guard let id = preset.modelID, id != models.activeModelID else { return }
        if models.installed.contains(where: { $0.id == id }) {
            pendingPresetModelID = nil
            Task { await models.select(id) }
        } else if let descriptor = models.catalog.first(where: { $0.id == id }) {
            pendingPresetModelID = id
            models.install(descriptor)
        }
    }

    private var presetCaption: String {
        if let id = pendingPresetModelID,
           models.downloadingModelIDs.contains(id) || models.installingModelIDs.contains(id),
           let name = models.catalog.first(where: { $0.id == id })?.displayName {
            return "Downloading \(name)…"
        }
        if let active = activeModelName {
            return "Using \(active) — pick a different one under All models."
        }
        return "No model yet — tap a preset to download one."
    }

    private var storageSummary: String {
        let count = models.installed.count
        let bytes = models.installed.compactMap { installed in
            installed.fileSize ?? models.catalog.first { $0.id == installed.id }?.fileSize
        }.reduce(Int64(0), +)
        let size = ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
        let noun = count == 1 ? "model" : "models"
        return count == 0
            ? "Local model storage — no models on disk"
            : "Local model storage — \(count) \(noun), \(size) on disk"
    }

    private func formattedSize(for id: String) -> String {
        if let bytes = models.installed.first(where: { $0.id == id })?.fileSize {
            return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
        }
        guard let descriptor = models.catalog.first(where: { $0.id == id }) else { return "" }
        return descriptor.formattedFileSize
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
            WVField(label: "Model") {
                TextField("", text: $controller.remoteModel).textFieldStyle(.wv)
            }
            WVField(label: configuration.hasAPIKey ? "API key (saved)" : "API key (optional)") {
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
            Text("HTTPS is required except for localhost or a private LAN endpoint. The API key is stored locally in Application Support with owner-only file permissions. Test Connection probes the draft above without saving it.")
                .font(.wvCaption)
                .foregroundStyle(Theme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Microphone

    private var microphoneSection: some View {
        sectionCard("Microphone", trailing: {
            Button { refreshMicrophone() } label: {
                Label("Refresh", systemImage: "arrow.triangle.2.circlepath")
            }
            .buttonStyle(.wvGhost)
        }) {
            HStack(spacing: 12) {
                deviceMenu(selection: Binding(
                    get: { microphone.preferredDeviceUID },
                    set: { microphone.preferredDeviceUID = $0 }
                ))
                if let activeDevice = microphone.activeDevice {
                    WVStatusPill(text: "Active: \(activeDevice.name)", color: Theme.success)
                } else {
                    Text("No input device detected")
                        .font(.wvCaption)
                        .foregroundStyle(Theme.warning)
                }
                Spacer(minLength: 0)
            }
            WVDisclosureCard(label: "Advanced") {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 7) {
                        HStack(spacing: 16) {
                            advancedLabel("Backup mic")
                            deviceMenu(selection: Binding(
                                get: { microphone.backupDeviceUID },
                                set: { microphone.backupDeviceUID = $0 }
                            ))
                            Spacer(minLength: 0)
                        }
                        Text("Used when your mic disconnects.")
                            .font(.wvCaption)
                            .foregroundStyle(Theme.textSecondary)
                    }
                    VStack(alignment: .leading, spacing: 7) {
                        HStack(spacing: 16) {
                            advancedLabel("Mic boost")
                            WVChipPicker(
                                selection: Binding(
                                    get: { microphone.boost },
                                    set: { microphone.boost = $0 }
                                ),
                                options: MicBoost.allCases,
                                label: { $0.label }
                            )
                            Spacer(minLength: 0)
                        }
                        Text("Turn up if your voice isn't being picked up.")
                            .font(.wvCaption)
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
            }
        }
    }

    private func advancedLabel(_ title: String) -> some View {
        Text(title)
            .font(.wv(13))
            .foregroundStyle(Theme.textPrimary)
            .frame(width: 90, alignment: .leading)
    }

    /// The reference device dropdown: System Default, every connected input
    /// device, and a shortcut to macOS Sound settings. A `nil` selection
    /// means "follow the system default".
    private func deviceMenu(selection: Binding<String?>) -> some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
        let selectedName = microphone.device(forUID: selection.wrappedValue)?.name
            ?? (selection.wrappedValue == nil ? "System Default" : "Disconnected")
        return Menu {
            Toggle("System Default", isOn: Binding(
                get: { selection.wrappedValue == nil },
                set: { _ in selection.wrappedValue = nil }
            ))
            Divider()
            ForEach(microphone.availableDevices) { device in
                Toggle(device.name, isOn: Binding(
                    get: { selection.wrappedValue == device.uid },
                    set: { _ in selection.wrappedValue = device.uid }
                ))
            }
            Divider()
            Button("Open macOS Sound Settings…") {
                if let url = URL(string: "x-apple.systempreferences:com.apple.Sound-Settings.extension") {
                    NSWorkspace.shared.open(url)
                }
            }
        } label: {
            HStack(spacing: 10) {
                Text(selectedName)
                    .font(.wv(13, .medium))
                    .foregroundStyle(Theme.textPrimary)
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Theme.textTertiary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Theme.inset, in: shape)
            .overlay(shape.strokeBorder(Theme.border, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
    }

    private func refreshMicrophone() {
        microphone.refreshDevices()
    }

    // MARK: Behavior

    private var behaviorSection: some View {
        sectionCard("Behavior") {
            settingRow(
                title: "Launch at login",
                caption: "Start WinterVoice automatically when you log in, ready in the menu bar."
            ) {
                Toggle("", isOn: $launchAtLogin.isEnabled)
                    .toggleStyle(.wv)
                    .labelsHidden()
            }
            if let error = launchAtLogin.lastError {
                Text(error).font(.wvCaption).foregroundStyle(Theme.danger)
            }
            WVDivider()
            settingRow(
                title: "Recording sounds",
                caption: "Chime when recording starts and stops."
            ) {
                Toggle("", isOn: $behavior.playsRecordingSounds)
                    .toggleStyle(.wv)
                    .labelsHidden()
            }
            WVDivider()
            settingRow(
                title: "Pause other audio while you talk",
                caption: "Mutes your speakers during recording so the mic stays clean."
            ) {
                Toggle("", isOn: $behavior.pausesOtherAudio)
                    .toggleStyle(.wv)
                    .labelsHidden()
            }
            WVDivider()
            settingRow(
                title: "Copy instead of typing it for you",
                caption: "Puts transcripts on your clipboard to paste yourself."
            ) {
                Toggle("", isOn: $behavior.copiesInsteadOfInserting)
                    .toggleStyle(.wv)
                    .labelsHidden()
            }
        }
    }

    // MARK: Floating widget

    private var widgetSection: some View {
        sectionCard("Floating Widget") {
            settingRow(
                title: "Show widget",
                caption: visibilityCaption
            ) {
                WVChipPicker(
                    selection: $widgetPreferences.visibility,
                    options: WidgetVisibility.allCases,
                    label: { $0.title },
                    grouped: true
                )
            }
            WVDivider()
            settingRow(
                title: "Follow cursor across monitors",
                caption: "Jumps to the monitor your cursor is on."
            ) {
                Toggle("", isOn: $widgetPreferences.followsCursor)
                    .toggleStyle(.wv)
                    .labelsHidden()
            }
            WVDivider()
            settingRow(
                title: "Lock position",
                caption: "Pin the pill above the dock and stop dragging."
            ) {
                Toggle("", isOn: $widgetPreferences.isLocked)
                    .toggleStyle(.wv)
                    .labelsHidden()
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("STYLE")
                    .font(.wvOverline)
                    .tracking(0.6)
                    .foregroundStyle(Theme.textTertiary)
                HStack(spacing: 12) {
                    ForEach(WidgetStyle.allCases, id: \.self) { style in
                        styleOptionCard(style)
                    }
                }
                .padding(.top, 4)
            }
            Text("Drag the pill to move it. Press Cmd + Shift + Space to bring it to the front.")
                .font(.wvCaption)
                .foregroundStyle(Theme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var visibilityCaption: String {
        switch widgetPreferences.visibility {
        case .always: "The pill stays on screen."
        case .whileRecording: "Appears only while you record."
        case .hidden: "The pill never appears."
        }
    }

    /// One reference style tile: a bordered card holding a miniature of the
    /// idle pill, with a check badge on the selected corner.
    private func styleOptionCard(_ style: WidgetStyle) -> some View {
        let selected = widgetPreferences.style == style
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous)
        return Button {
            widgetPreferences.style = style
        } label: {
            stylePreviewPill(style)
                .frame(maxWidth: .infinity, minHeight: 64)
                .background(shape.fill(Theme.inset))
                .overlay(
                    shape.strokeBorder(
                        selected ? Theme.chipSelectedBorder : Theme.border,
                        lineWidth: selected ? 1.5 : 1
                    )
                )
                .overlay(alignment: .topTrailing) {
                    if selected {
                        Circle()
                            .fill(Theme.emphasis)
                            .frame(width: 20, height: 20)
                            .overlay(
                                Image(systemName: "checkmark")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(Theme.textOnEmphasis)
                            )
                            .offset(x: 6, y: -6)
                    }
                }
                .contentShape(shape)
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .padding(.top, 6)
    }

    /// Miniature of what the idle widget looks like in each style.
    @ViewBuilder
    private func stylePreviewPill(_ style: WidgetStyle) -> some View {
        let pill = Capsule().fill(Color(hex: 0x0A0A0B))
        let border = Capsule().strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
        switch style {
        case .labeled:
            HStack(spacing: 6) {
                WVBrandMark(size: 15)
                Text("WinterVoice")
                    .font(.wv(11.5, .semibold))
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 6)
            .background(pill)
            .overlay(border)
        case .icon:
            WVBrandMark(size: 15)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(pill)
                .overlay(border)
        case .minimal:
            Image(systemName: "waveform")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.white.opacity(0.8))
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(pill)
                .overlay(border)
        }
    }

    /// A reference settings row: title + caption on the left, the control on
    /// the right edge of the card.
    private func settingRow(
        title: String,
        caption: String,
        @ViewBuilder trailing: () -> some View
    ) -> some View {
        HStack(alignment: .center, spacing: Theme.Space.sm) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.wvRowTitle)
                    .foregroundStyle(Theme.textPrimary)
                Text(caption)
                    .font(.wvCaption)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: Theme.Space.md)
            trailing()
        }
    }

    // MARK: Theme

    private var themeSection: some View {
        sectionCard("Theme") {
            HStack(spacing: 12) {
                ForEach(ThemeMode.allCases) { mode in
                    themeOptionCard(mode)
                }
            }
        }
    }

    /// One reference theme tile: a mini palette swatch and label, with a check
    /// badge on the selected option.
    private func themeOptionCard(_ mode: ThemeMode) -> some View {
        let selected = theme.mode == mode
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous)
        return Button {
            theme.mode = mode
        } label: {
            HStack(spacing: 10) {
                themeSwatch(mode)
                Text(mode.title)
                    .font(.wvRowTitle)
                    .foregroundStyle(Theme.textPrimary)
                Spacer(minLength: 0)
                if selected {
                    Circle()
                        .fill(Theme.emphasis)
                        .frame(width: 20, height: 20)
                        .overlay(
                            Image(systemName: "checkmark")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(Theme.textOnEmphasis)
                        )
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity)
            .background(shape.fill(selected ? Theme.surfaceElevated : Theme.inset))
            .overlay(
                shape.strokeBorder(
                    selected ? Theme.chipSelectedBorder : Theme.border,
                    lineWidth: selected ? 1.5 : 1
                )
            )
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
    }

    /// Miniature toggle-style preview of the mode's palette.
    private func themeSwatch(_ mode: ThemeMode) -> some View {
        let background: Color = mode == .black ? Color(hex: 0x0A0A0A) : .white
        let dot: Color = mode == .black ? .white : Color(hex: 0x18181B)
        return Capsule()
            .fill(background)
            .frame(width: 36, height: 20)
            .overlay(Capsule().strokeBorder(Theme.borderStrong, lineWidth: 1))
            .overlay(alignment: .leading) {
                Circle()
                    .fill(dot)
                    .frame(width: 12, height: 12)
                    .padding(.leading, 4)
            }
            .overlay(alignment: .trailing) {
                Circle()
                    .fill(dot.opacity(0.35))
                    .frame(width: 7, height: 7)
                    .padding(.trailing, 6)
            }
    }

    // MARK: Updates

    private var updatesSection: some View {
        sectionCard("Updates", trailing: {
            if updates.state == .checking {
                ProgressView().controlSize(.small)
            } else {
                Button("Check for Updates") { updates.checkNow() }
                    .buttonStyle(.wvSecondary)
            }
        }) {
            settingRow(
                title: "WinterVoice v\(updates.currentVersion)",
                caption: updateCaption
            ) {
                if case .available = updates.state {
                    WVStatusPill(text: "Update available", color: Theme.accent, filled: true)
                } else if updates.state == .upToDate {
                    WVStatusPill(text: "Up to date", color: Theme.success)
                }
            }
            if case .available(let update) = updates.state {
                updateCard(update)
            }
        }
    }

    private var updateCaption: String {
        switch updates.state {
        case .idle: "Checks GitHub Releases once a day."
        case .checking: "Checking GitHub Releases…"
        case .upToDate: "You're on the latest version."
        case .available(let update): "Version \(update.version) is ready to download."
        case .failed(let message): message
        }
    }

    /// The what's-new card: release highlights straight from the GitHub
    /// release notes, so users see what they get before downloading.
    private func updateCard(_ update: AvailableUpdate) -> some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous)
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: Theme.Space.sm) {
                WVIconBadge(systemImage: "sparkles", tint: Theme.accent, size: 30)
                Text("What's new in v\(update.version)")
                    .font(.wvRowTitle)
                    .foregroundStyle(Theme.textPrimary)
                Spacer(minLength: 0)
            }
            if update.highlights.isEmpty {
                Text("See the release page for the full notes.")
                    .font(.wvCaption)
                    .foregroundStyle(Theme.textSecondary)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(update.highlights, id: \.self) { highlight in
                        HStack(alignment: .top, spacing: 8) {
                            Circle()
                                .fill(Theme.textTertiary)
                                .frame(width: 4, height: 4)
                                .padding(.top, 6)
                            Text(highlightText(highlight))
                                .font(.wv(12.5))
                                .foregroundStyle(Theme.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
            HStack(spacing: 10) {
                Button("Download Update") { updates.download(update) }
                    .buttonStyle(.wvPrimary)
                Button("View Release") { updates.viewRelease(update) }
                    .buttonStyle(.wvSecondary)
                Button("Skip This Version") { updates.skip(update) }
                    .buttonStyle(.wvGhost)
                Spacer(minLength: 0)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(shape.fill(Theme.inset))
        .overlay(shape.strokeBorder(Theme.border, lineWidth: 1))
    }

    /// Release bullets carry inline markdown (bold, links); render it when it
    /// parses, fall back to the raw line when it doesn't.
    private func highlightText(_ highlight: String) -> AttributedString {
        (try? AttributedString(markdown: highlight)) ?? AttributedString(highlight)
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

    // MARK: Section scaffold

    private func sectionCard(
        _ title: String,
        subtitle: String? = nil,
        @ViewBuilder content: () -> some View
    ) -> some View {
        sectionCard(title, subtitle: subtitle, trailing: { EmptyView() }, content: content)
    }

    private func sectionCard(
        _ title: String,
        subtitle: String? = nil,
        @ViewBuilder trailing: () -> some View,
        @ViewBuilder content: () -> some View
    ) -> some View {
        WVCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .center, spacing: Theme.Space.sm) {
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
                    Spacer(minLength: 0)
                    trailing()
                }
                content()
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
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
    @ObservedObject private var theme = ThemeStore.shared

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
        .preferredColorScheme(theme.mode.colorScheme)
        .onAppear { presenter.refreshPermissions() }
    }
}
