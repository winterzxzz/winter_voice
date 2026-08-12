import AVFoundation
import Speech

@MainActor
final class AppleSpeechTranscriber: SpeechTranscribing {
    private let audioEngine = AVAudioEngine()
    private var recognitionTask: SFSpeechRecognitionTask?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var finalText = ""
    private var stopContinuation: CheckedContinuation<String, Error>?
    private var isInputTapInstalled = false

    func start() async throws {
        guard let recognizer = SFSpeechRecognizer(), recognizer.isAvailable else {
            throw DictationFailure(message: "Speech recognition is unavailable.", recovery: "Check your language and Speech Recognition settings.")
        }
        guard recognizer.supportsOnDeviceRecognition else {
            throw DictationFailure(
                message: "On-device recognition is not supported for this language.",
                recovery: "Choose a macOS language with on-device dictation support. WinterVoice will not send audio to a server."
            )
        }

        tearDownAudio()
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = true
        recognitionRequest = request
        finalText = ""

        let input = audioEngine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            throw DictationFailure(message: "No microphone input is available.", recovery: "Connect or select a microphone and try again.")
        }
        input.installTap(onBus: 0, bufferSize: 1_024, format: format) { [weak request] buffer, _ in
            request?.append(buffer)
        }
        isInputTapInstalled = true

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor in
                guard let self else { return }
                if let result {
                    self.finalText = result.bestTranscription.formattedString
                    if result.isFinal { self.completeStop(with: .success(self.finalText)) }
                } else if let error {
                    self.completeStop(with: .failure(DictationFailure(
                        message: "On-device recognition failed.",
                        recovery: error.localizedDescription
                    )))
                }
            }
        }

        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch {
            tearDownAudio()
            recognitionTask?.cancel()
            recognitionTask = nil
            recognitionRequest = nil
            throw DictationFailure(message: "Could not start the microphone.", recovery: error.localizedDescription)
        }
    }

    func stop() async throws -> String {
        guard recognitionRequest != nil else {
            throw DictationFailure(message: "Recording was not active.", recovery: "Hold Right Option and try again.")
        }
        tearDownAudio()
        recognitionRequest?.endAudio()

        return try await withCheckedThrowingContinuation { continuation in
            stopContinuation = continuation
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(3))
                guard let self, self.stopContinuation != nil else { return }
                if self.finalText.isEmpty {
                    self.completeStop(with: .failure(DictationFailure(
                        message: "No speech was recognized.",
                        recovery: "Hold Right Option and speak clearly before releasing it."
                    )))
                } else {
                    self.completeStop(with: .success(self.finalText))
                }
            }
        }
    }

    func cancel() {
        tearDownAudio()
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionRequest = nil
        recognitionTask = nil
        stopContinuation?.resume(throwing: CancellationError())
        stopContinuation = nil
    }

    private func tearDownAudio() {
        if audioEngine.isRunning { audioEngine.stop() }
        if isInputTapInstalled {
            audioEngine.inputNode.removeTap(onBus: 0)
            isInputTapInstalled = false
        }
    }

    private func completeStop(with result: Result<String, Error>) {
        guard let continuation = stopContinuation else { return }
        stopContinuation = nil
        recognitionRequest = nil
        recognitionTask = nil
        continuation.resume(with: result)
    }
}
