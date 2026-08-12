import Foundation

@MainActor
final class DictationInteractor: DictationInteracting {
    private let relay: DictationStateRelay
    private let transcriber: SpeechTranscribing
    private let injector: TextInjecting
    private let permissions: PermissionManaging
    private var machine = DictationStateMachine()
    private var target: TextInsertionTarget?
    private var preparationTask: Task<Void, Never>?
    private var releasePending = false

    init(
        relay: DictationStateRelay,
        transcriber: SpeechTranscribing,
        injector: TextInjecting,
        permissions: PermissionManaging
    ) {
        self.relay = relay
        self.transcriber = transcriber
        self.injector = injector
        self.permissions = permissions
    }

    func beginPushToTalk() {
        guard machine.state == .idle else { return }
        releasePending = false
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
            Task { [weak self] in await self?.finishDictation() }
        default:
            break
        }
    }

    private func prepareAndRecord() async {
        do {
            try await requirePermission(.microphone)
            try await requirePermission(.speechRecognition)
            try await requirePermission(.inputMonitoring)
            guard permissions.snapshot().accessibility == .authorized else {
                throw DictationFailure(
                    message: "Accessibility permission is required.",
                    recovery: "Open Settings and allow WinterVoice in Privacy & Security → Accessibility."
                )
            }
            target = try injector.captureTarget()
            try await transcriber.start()
            move(to: .recording)
            if releasePending { await finishDictation() }
        } catch {
            fail(error)
        }
    }

    private func finishDictation() async {
        guard machine.state == .recording, let target else { return }
        move(to: .processing)
        do {
            let text = try await transcriber.stop().trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else {
                throw DictationFailure(message: "No speech was recognized.", recovery: "Hold Right Option and try speaking again.")
            }
            move(to: .inserting)
            try await injector.insert(text, into: target)
            injector.discard(target)
            self.target = nil
            move(to: .idle)
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
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(4))
            guard let self, case .failed = self.machine.state else { return }
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
