import Foundation

@MainActor
final class DictationInteractor: DictationInteracting {
    private let relay: DictationStateRelay
    private let transcriber: SpeechTranscribing
    private let injector: TextInjecting
    private let permissions: PermissionManaging
    private let textProcessor: TextProcessing
    private let history: HistoryRecording
    private let usage: UsageRecording
    private let behavior: DictationBehaviorProviding
    private let transcriptCopier: TranscriptCopying
    private let failureResetDelay: Duration
    private var machine = DictationStateMachine()
    private var target: TextInsertionTarget?
    /// Decided when the session starts, so flipping the setting mid-recording
    /// cannot strand a session that never captured a target.
    private var usesClipboardDelivery = false
    private var preparationTask: Task<Void, Never>?
    private var finishTask: Task<Void, Never>?
    private var failureResetTask: Task<Void, Never>?
    private var releasePending = false
    private var recordingStartedAt: Date?

    init(
        relay: DictationStateRelay,
        transcriber: SpeechTranscribing,
        injector: TextInjecting,
        permissions: PermissionManaging,
        textProcessor: TextProcessing = IdentityTextProcessor(),
        history: HistoryRecording = NoopHistoryRecorder(),
        usage: UsageRecording = NoopUsageRecorder(),
        behavior: DictationBehaviorProviding = DefaultDictationBehavior(),
        transcriptCopier: TranscriptCopying = SystemTranscriptCopier(),
        failureResetDelay: Duration = .seconds(4)
    ) {
        self.relay = relay
        self.transcriber = transcriber
        self.injector = injector
        self.permissions = permissions
        self.textProcessor = textProcessor
        self.history = history
        self.usage = usage
        self.behavior = behavior
        self.transcriptCopier = transcriptCopier
        self.failureResetDelay = failureResetDelay
    }

    func beginPushToTalk() {
        // A new press dismisses a lingering failure banner instead of being
        // silently swallowed for the rest of the auto-reset window.
        if case .failed = machine.state {
            failureResetTask?.cancel()
            failureResetTask = nil
            move(to: .idle)
        }
        // A press while transcribing is the only escape from a long
        // transcription: abort it instead of silently swallowing the press.
        // cancel() aborts a local whisper run; cancelling the tasks propagates
        // Swift task cancellation into an in-flight remote URLSession request.
        if machine.state == .processing {
            transcriber.cancel()
            preparationTask?.cancel()
            finishTask?.cancel()
            return
        }
        guard machine.state == .idle else { return }
        releasePending = false
        do {
            try transcriber.validateConfiguration()
        } catch {
            fail(error)
            return
        }
        move(to: .preparing)
        preparationTask = Task { [weak self] in
            await self?.prepareAndRecord()
        }
    }

    func endPushToTalk() {
        switch machine.state {
        case .preparing:
            releasePending = true
        case .recording:
            finishTask = Task { [weak self] in await self?.finishDictation() }
        default:
            break
        }
    }

    /// Toggle-mode key-down: starts a session when none is active, otherwise
    /// finishes it. During processing this falls through to the abort branch
    /// in beginPushToTalk; during inserting the press is meaningless.
    func togglePushToTalk() {
        switch machine.state {
        case .idle, .failed, .processing:
            beginPushToTalk()
        case .preparing, .recording:
            endPushToTalk()
        case .inserting:
            break
        }
    }

    private func prepareAndRecord() async {
        do {
            // Copy mode never touches the focused field, so it needs neither
            // Accessibility nor a captured target.
            usesClipboardDelivery = behavior.copiesInsteadOfInserting
            // Capture the focused field as close to the key press as possible,
            // but never synchronously inside the event-tap callback: AX lookups
            // are IPC into the focused app and can stall past the tap watchdog.
            let snapshot = permissions.snapshot()
            if !usesClipboardDelivery,
               snapshot.microphone == .authorized,
               snapshot.inputMonitoring == .authorized,
               snapshot.accessibility == .authorized {
                target = try injector.captureTarget()
            }
            try await requirePermission(.microphone)
            try await requirePermission(.inputMonitoring)
            if !usesClipboardDelivery {
                guard permissions.snapshot().accessibility == .authorized else {
                    throw DictationFailure(
                        message: "Accessibility permission is required.",
                        recovery: "Open Settings and allow WinterVoice in Privacy & Security → Accessibility."
                    )
                }
                if target == nil { target = try injector.captureTarget() }
            }
            try await transcriber.start()
            move(to: .recording)
            recordingStartedAt = Date()
            if releasePending { await finishDictation() }
        } catch {
            fail(error)
        }
    }

    private func finishDictation() async {
        guard machine.state == .recording, usesClipboardDelivery || target != nil else { return }
        let speakingSeconds = recordingStartedAt.map { Date().timeIntervalSince($0) } ?? 0
        recordingStartedAt = nil
        move(to: .processing)
        do {
            let rawText = try await transcriber.stop()
            let text = textProcessor.process(rawText)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else {
                throw DictationFailure(message: "No speech was recognized.", recovery: "Hold the configured push-to-talk key and try speaking again.")
            }
            move(to: .inserting)
            if usesClipboardDelivery {
                guard transcriptCopier.copy(text) else {
                    throw DictationFailure(
                        message: "Could not copy the transcript.",
                        recovery: "Try dictating again."
                    )
                }
                history.record(text: text)
            } else if let target {
                let outcome = try await injector.insert(text, into: target)
                // Text dictated into a password field must never reach History.
                if !outcome.landedInSecureField {
                    history.record(text: text)
                }
                injector.discard(target)
                self.target = nil
            }
            usage.recordSession(
                words: text.split(whereSeparator: \.isWhitespace).count,
                speakingSeconds: speakingSeconds
            )
            move(to: .idle)
        } catch is CancellationError {
            fail(DictationFailure(
                message: "Transcription canceled.",
                recovery: "Hold the push-to-talk key and dictate again."
            ))
        } catch {
            fail(error)
        }
    }

    private func requirePermission(_ permission: AppPermission) async throws {
        let current = permissions.snapshot()[permission]
        let status = current == .notDetermined ? await permissions.request(permission) : current
        guard status == .authorized else {
            throw DictationFailure(
                message: "\(permission.title) permission is required.",
                recovery: "Open WinterVoice Settings to grant access."
            )
        }
    }

    private func fail(_ error: Error) {
        transcriber.cancel()
        if let target { injector.discard(target) }
        target = nil
        let failure = error as? DictationFailure ?? DictationFailure(
            message: "Dictation failed.",
            recovery: error.localizedDescription
        )
        move(to: .failed(failure))
        failureResetTask?.cancel()
        let delay = failureResetDelay
        failureResetTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let self, case .failed = self.machine.state else { return }
            self.move(to: .idle)
        }
    }

    private func move(to state: DictationState) {
        do {
            try machine.transition(to: state)
            relay.publish(state)
        } catch {
            assertionFailure("Invalid dictation transition: \(error)")
        }
    }
}
