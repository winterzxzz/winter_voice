import Foundation

@MainActor
protocol DictationInteracting: AnyObject {
    func beginPushToTalk()
    func endPushToTalk()
}

@MainActor
protocol TextProcessing: AnyObject {
    func process(_ text: String) -> String
}

@MainActor
protocol HistoryRecording: AnyObject {
    func record(text: String)
}

@MainActor
final class IdentityTextProcessor: TextProcessing {
    func process(_ text: String) -> String { text }
}

@MainActor
final class NoopHistoryRecorder: HistoryRecording {
    func record(text: String) {}
}

@MainActor
protocol SpeechTranscribing: AnyObject {
    func validateConfiguration() throws
    func start() async throws
    func stop() async throws -> String
    func cancel()
}

struct RecordedAudio: Sendable {
    let samples: [Float]
    let sampleRate: Double
}

@MainActor
protocol AudioRecording: AnyObject {
    func start() throws
    func stop() throws -> RecordedAudio
    func cancel()
}

@MainActor
protocol TextInjecting: AnyObject {
    func captureTarget() throws -> TextInsertionTarget
    @discardableResult
    func insert(_ text: String, into target: TextInsertionTarget) async throws -> InsertionOutcome
    func discard(_ target: TextInsertionTarget)
}

@MainActor
protocol PermissionManaging: AnyObject {
    func snapshot() -> PermissionSnapshot
    func request(_ permission: AppPermission) async -> PermissionStatus
}

@MainActor
protocol HotkeyCaptureSuspending: AnyObject {
    func suspendMatching()
    func resumeMatching()
}
