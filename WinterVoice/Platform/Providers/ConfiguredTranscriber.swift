import Foundation

@MainActor
final class ConfiguredTranscriber: SpeechTranscribing {
    private let recorder: AudioRecording
    private let configuration: ProviderConfigurationStore
    private let models: ModelManager
    private let remoteProvider: RemoteTranscriptionProvider
    private let localRuntime: any LocalTranscriptionRunning

    init(
        recorder: AudioRecording,
        configuration: ProviderConfigurationStore,
        models: ModelManager,
        remoteProvider: RemoteTranscriptionProvider = .init(),
        localRuntime: any LocalTranscriptionRunning = WhisperContextActor()
    ) {
        self.recorder = recorder
        self.configuration = configuration
        self.models = models
        self.remoteProvider = remoteProvider
        self.localRuntime = localRuntime
    }

    func validateConfiguration() throws {
        let readiness = configuration.readiness(localModels: models)
        guard readiness.isReady else {
            let message: String
            switch configuration.mode {
            case .local where models.activeModel == nil:
                message = "No local model is selected."
            case .local:
                message = "Local transcription runtime is unavailable."
            case .remote:
                message = "Remote transcription provider is not configured."
            }
            throw DictationFailure(message: message, recovery: readiness.detail)
        }
    }

    func start() async throws {
        try validateConfiguration()
        try recorder.start()
    }

    func stop() async throws -> String {
        let audio = try recorder.stop()
        switch configuration.mode {
        case .local:
            guard let modelURL = models.activeModelURL else {
                throw DictationFailure(
                    message: "No local model is selected.",
                    recovery: "Download and select a model in Transcription settings."
                )
            }
            let language = models.activeModel?.isEnglishOnly == true ? "en" : nil
            return try await localRuntime.transcribe(audio, modelURL: modelURL, language: language)
        case .remote:
            let key = try configuration.apiKey()
            return try await remoteProvider.transcribe(
                audio: audio,
                configuration: configuration.remote,
                apiKey: key
            )
        }
    }

    func cancel() {
        recorder.cancel()
        localRuntime.cancelActiveTranscription()
    }
}
