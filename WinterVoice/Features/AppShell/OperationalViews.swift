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

            if !permissionsReady {
                WVCard {
                    HStack(alignment: .top, spacing: Theme.Space.sm) {
                        WVIconBadge(systemImage: "exclamationmark.triangle.fill", tint: Theme.warning)
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Permissions need attention")
                                .font(.wvHeadline)
                                .foregroundStyle(Theme.warning)
                            Text("WinterVoice needs Microphone, Input Monitoring, and Accessibility for audio capture, the global hotkey, and safe insertion.")
                                .font(.wvBody)
                                .foregroundStyle(Theme.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                            Button("Fix Permission Issues") { presenter.navigate(to: .settings) }
                                .buttonStyle(.wvPrimary)
                                .padding(.top, 2)
                        }
                        Spacer(minLength: 0)
                    }
                }
            }

            UsageStatsSection(store: presenter.usageStats)

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
        WVPage(
            icon: "keyboard",
            title: "Shortcuts",
            subtitle: "Set the keys that control recording."
        ) {
            WVCard(padding: 6) {
                VStack(spacing: 0) {
                    recordingShortcutRow(
                        icon: "mic",
                        title: "Push-to-Talk",
                        subtitle: "Hold to record. Release to insert your words.",
                        mode: .holdToTalk,
                        showsClear: true
                    )
                    WVDivider().padding(.horizontal, 12)
                    recordingShortcutRow(
                        icon: "record.circle",
                        title: "Toggle Recording",
                        subtitle: "Press once to start hands-free. Press again to stop and insert.",
                        mode: .toggle,
                        showsClear: false
                    )
                    WVDivider().padding(.horizontal, 12)
                    showWidgetRow
                }
            }

            resetLine

            WVDisclosureCard(label: "Troubleshooting", chevronLeading: true) {
                troubleshooting
            }
        } trailing: {
            Button { presenter.refreshPermissions() } label: {
                Label("Refresh", systemImage: "arrow.triangle.2.circlepath")
            }
            .buttonStyle(.wvGhost)
        }
    }

    /// One reference-style shortcut row. Whichever row the user last captured a
    /// key for becomes the active recording mode; the other reads "Not set".
    private func recordingShortcutRow(
        icon: String,
        title: String,
        subtitle: String,
        mode: RecordingMode,
        showsClear: Bool
    ) -> some View {
        let isActive = binding.recordingMode == mode
        return HStack(alignment: .center, spacing: Theme.Space.sm) {
            WVIconBadge(systemImage: icon)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.wvRowTitle)
                    .foregroundStyle(Theme.textPrimary)
                Text(subtitle)
                    .font(.wvCaption)
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer(minLength: Theme.Space.md)
            VStack(alignment: .trailing, spacing: 5) {
                HStack(spacing: 8) {
                    if isActive {
                        WVKeycapChord(keys: binding.selection.keyLabels)
                    } else {
                        Text("Not set")
                            .font(.wvKeycap)
                            .foregroundStyle(Theme.textTertiary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(
                                Theme.inset,
                                in: RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous)
                            )
                    }
                    HotkeyRecorder(
                        captureSuspender: captureSuspender,
                        onRecord: { recorded in
                            binding.selection = recorded
                            binding.recordingMode = mode
                        }
                    )
                    .fixedSize()
                    if showsClear {
                        Button("Clear") {
                            binding.selection = .function
                            binding.recordingMode = .holdToTalk
                        }
                        .buttonStyle(.wvGhost)
                        .disabled(binding.selection == .function && binding.recordingMode == .holdToTalk)
                    }
                }
                if isActive {
                    HStack(spacing: 5) {
                        Circle()
                            .fill(listening ? Theme.success : Theme.warning)
                            .frame(width: 5, height: 5)
                        Text(listening ? "Active" : "Needs attention")
                            .font(.wv(11, .medium))
                            .foregroundStyle(listening ? Theme.success : Theme.warning)
                    }
                }
            }
        }
        .padding(12)
    }

    private var showWidgetRow: some View {
        HStack(alignment: .center, spacing: Theme.Space.sm) {
            WVIconBadge(systemImage: "macwindow.on.rectangle")
            VStack(alignment: .leading, spacing: 2) {
                Text("Show Widget")
                    .font(.wvRowTitle)
                    .foregroundStyle(Theme.textPrimary)
                Text("Brings the floating pill to the front. Doesn't start recording.")
                    .font(.wvCaption)
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer(minLength: Theme.Space.md)
            WVKeycapChord(keys: ["Cmd", "Shift", "Space"])
            Text("Fixed")
                .font(.wvCaption)
                .foregroundStyle(Theme.textTertiary)
        }
        .padding(12)
    }

    private var resetLine: some View {
        HStack(spacing: 10) {
            Text("Push-to-talk:")
                .font(.wvBody)
                .foregroundStyle(Theme.textSecondary)
            Button("Reset to default · Fn / Globe") {
                binding.selection = .function
                binding.recordingMode = .holdToTalk
            }
            .buttonStyle(.wvSecondary)
            .disabled(binding.selection == .function && binding.recordingMode == .holdToTalk)
            Text("— or capture your own above.")
                .font(.wvCaption)
                .foregroundStyle(Theme.textTertiary)
        }
    }

    private var troubleshooting: some View {
        VStack(alignment: .leading, spacing: 10) {
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
                .fixedSize(horizontal: false, vertical: true)
            Text("Click Change, then press a key, a combination, or hold modifiers such as ⌥⇧ and release them together. Fn / Globe is the default. Changes apply immediately and are saved for future launches. If the listener is not active, check Input Monitoring in Settings.")
                .font(.wvCaption)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Hotkey recorder (AppKit)

/// The reference "Change" button. Clicking it captures the next key press or
/// modifier chord globally; Escape cancels.
private struct HotkeyRecorder: NSViewRepresentable {
    var captureSuspender: HotkeyCaptureSuspending?
    var onRecord: (HotkeyBinding) -> Void

    func makeNSView(context: Context) -> HotkeyRecorderView {
        let view = HotkeyRecorderView()
        view.onRecord = onRecord
        view.captureSuspender = captureSuspender
        return view
    }

    func updateNSView(_ view: HotkeyRecorderView, context: Context) {
        view.onRecord = onRecord
        view.captureSuspender = captureSuspender
    }
}

private final class HotkeyRecorderView: NSButton {
    var onRecord: ((HotkeyBinding) -> Void)?
    weak var captureSuspender: (any HotkeyCaptureSuspending & AnyObject)?
    private var isRecording = false
    private var pendingModifierFlags: CGEventFlags = []

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        isBordered = false
        setButtonType(.momentaryChange)
        wantsLayer = true
        layer?.cornerRadius = 8
        focusRingType = .none
        target = self
        action = #selector(beginRecording)
        refreshAppearance()
    }

    required init?(coder: NSCoder) { nil }

    override var acceptsFirstResponder: Bool { true }

    override var intrinsicContentSize: NSSize {
        var size = super.intrinsicContentSize
        size.width += 24
        size.height = 28
        return size
    }

    @objc private func beginRecording() {
        guard !isRecording else { return }
        isRecording = true
        pendingModifierFlags = []
        // The global tap keeps matching the CURRENT binding while a new one is
        // recorded; pressing its modifier here must not start a dictation.
        captureSuspender?.suspendMatching()
        window?.makeFirstResponder(self)
        refreshAppearance()
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
            setTitle(
                "\(HotkeyBinding.modifierChord(pendingModifierFlags).title) · release",
                color: NSColor(Theme.textPrimary)
            )
            invalidateIntrinsicContentSize()
            return
        }
        guard !pendingModifierFlags.isEmpty else { return }
        onRecord?(.modifierChord(pendingModifierFlags))
        finishRecording()
    }

    override func resignFirstResponder() -> Bool {
        isRecording = false
        captureSuspender?.resumeMatching()
        refreshAppearance()
        return super.resignFirstResponder()
    }

    private func finishRecording() {
        isRecording = false
        pendingModifierFlags = []
        captureSuspender?.resumeMatching()
        refreshAppearance()
    }

    private func refreshAppearance() {
        if isRecording {
            layer?.backgroundColor = NSColor(Theme.textPrimary).withAlphaComponent(0.1).cgColor
            layer?.borderWidth = 1
            layer?.borderColor = NSColor(Theme.textPrimary).withAlphaComponent(0.25).cgColor
            setTitle("Press keys…", color: NSColor(Theme.textPrimary))
        } else {
            layer?.backgroundColor = NSColor(Theme.emphasis).cgColor
            layer?.borderWidth = 0
            setTitle("Change", color: NSColor(Theme.textOnEmphasis))
        }
        invalidateIntrinsicContentSize()
    }

    private func setTitle(_ string: String, color: NSColor) {
        attributedTitle = NSAttributedString(
            string: string,
            attributes: [
                .font: NSFont(name: "Inter-SemiBold", size: 12)
                    ?? NSFont.systemFont(ofSize: 12, weight: .semibold),
                .foregroundColor: color,
            ]
        )
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
