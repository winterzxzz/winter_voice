import Foundation
import whisper

protocol LocalTranscriptionRunning: Sendable {
    func transcribe(_ audio: RecordedAudio, modelURL: URL, language: String?) async throws -> String
    func cancelActiveTranscription()
    func unloadContext() async
}

actor WhisperContextActor: LocalTranscriptionRunning {
    private final class ContextHandle: @unchecked Sendable {
        let pointer: OpaquePointer

        init(_ pointer: OpaquePointer) { self.pointer = pointer }
        deinit { whisper_free(pointer) }
    }

    private final class AbortFlag: @unchecked Sendable {
        private let lock = NSLock()
        private var raised = false

        func raise() { lock.lock(); raised = true; lock.unlock() }
        func reset() { lock.lock(); raised = false; lock.unlock() }
        var isRaised: Bool {
            lock.lock()
            defer { lock.unlock() }
            return raised
        }
    }

    // Reachable without the actor's executor: while whisper_full blocks the
    // executor, an isolated cancel could never run until the work it is meant
    // to abort had already finished.
    private nonisolated let abortFlag = AbortFlag()
    private var context: ContextHandle?
    private var loadedModelURL: URL?

    nonisolated func cancelActiveTranscription() {
        abortFlag.raise()
    }

    /// Releases the loaded whisper context (up to ~1.5 GB resident for the
    /// Small model). Called when the active model is deleted or deselected and
    /// when the provider mode switches to remote.
    func unloadContext() {
        context = nil
        loadedModelURL = nil
    }

    func transcribe(_ audio: RecordedAudio, modelURL: URL, language: String?) throws -> String {
        guard audio.sampleRate == 16_000 else {
            throw DictationFailure(
                message: "Local transcription received unsupported audio.",
                recovery: "WinterVoice expects mono 16 kHz audio for whisper.cpp."
            )
        }
        guard !audio.samples.isEmpty else {
            throw DictationFailure(
                message: "No speech was recorded.",
                recovery: "Hold the push-to-talk shortcut while speaking, then release it."
            )
        }

        abortFlag.reset()
        let context = try loadContext(for: modelURL)
        var parameters = whisper_full_default_params(WHISPER_SAMPLING_GREEDY)
        parameters.print_realtime = false
        parameters.print_progress = false
        parameters.print_timestamps = false
        parameters.print_special = false
        parameters.translate = false
        parameters.no_context = true
        parameters.single_segment = false
        parameters.n_threads = Int32(max(1, min(8, ProcessInfo.processInfo.processorCount - 2)))
        parameters.abort_callback = { userData in
            guard let userData else { return false }
            return Unmanaged<AbortFlag>.fromOpaque(userData).takeUnretainedValue().isRaised
        }
        parameters.abort_callback_user_data = Unmanaged.passUnretained(abortFlag).toOpaque()

        let selectedLanguage = language?.trimmingCharacters(in: .whitespacesAndNewlines)
        let languageCode = selectedLanguage?.isEmpty == false ? selectedLanguage! : "auto"
        let result = languageCode.withCString { languagePointer in
            parameters.language = languagePointer
            return audio.samples.withUnsafeBufferPointer { samples in
                whisper_full(context, parameters, samples.baseAddress, Int32(samples.count))
            }
        }
        // An aborted run can still return 0 with partial segments.
        if abortFlag.isRaised { throw CancellationError() }
        guard result == 0 else {
            throw DictationFailure(
                message: "Local transcription failed.",
                recovery: "The selected model could not process this recording. Try again or select another model."
            )
        }

        var text = ""
        for index in 0..<whisper_full_n_segments(context) {
            guard let segment = whisper_full_get_segment_text(context, index) else { continue }
            text += String(cString: segment)
        }
        let transcription = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !transcription.isEmpty else {
            throw DictationFailure(
                message: "No speech was recognized.",
                recovery: "Try speaking closer to the microphone or recording a longer phrase."
            )
        }
        return transcription
    }

    private func loadContext(for modelURL: URL) throws -> OpaquePointer {
        if loadedModelURL == modelURL, let context { return context.pointer }
        guard FileManager.default.fileExists(atPath: modelURL.path) else {
            throw DictationFailure(
                message: "The selected local model is missing.",
                recovery: "Download or reinstall the model from Transcription settings."
            )
        }

        context = nil
        loadedModelURL = nil
        var parameters = whisper_context_default_params()
        parameters.flash_attn = true
        guard let loaded = whisper_init_from_file_with_params(modelURL.path, parameters) else {
            throw DictationFailure(
                message: "The selected local model could not be loaded.",
                recovery: "Reinstall the model and try again."
            )
        }
        context = ContextHandle(loaded)
        loadedModelURL = modelURL
        return loaded
    }
}
