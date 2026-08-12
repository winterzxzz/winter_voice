import Foundation

@MainActor
final class ConfiguredTranscriber: SpeechTranscribing {
    private let recorder: AudioRecording
    private let configuration: ProviderConfigurationStore
    private let models: ModelManager
    private let remoteProvider: RemoteTranscriptionProvider

    init(
        recorder: AudioRecording,
        configuration: ProviderConfigurationStore,
        models: ModelManager,
        remoteProvider: RemoteTranscriptionProvider = .init()
    ) {
        self.recorder = recorder
        self.configuration = configuration
        self.models = models
        self.remoteProvider = remoteProvider
    }

    func validateConfiguration() throws {
        let readiness = configuration.readiness(localModels: models)
        guard readiness.isReady else {
            throw DictationFailure(message: "No transcription provider is configured.", recovery: readiness.detail)
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
            throw DictationFailure(
                message: "The local transcription runtime is unavailable.",
                recovery: "WinterVoice needs an approved whisper.cpp dependency and published model artifact."
            )
        case .remote:
            let key = try configuration.apiKey()
            return try await remoteProvider.transcribe(
                audio: audio,
                configuration: configuration.remote,
                apiKey: key
            )
        }
    }

    func cancel() { recorder.cancel() }
}
