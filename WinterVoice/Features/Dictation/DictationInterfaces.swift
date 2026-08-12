import Foundation

@MainActor
protocol DictationInteracting: AnyObject {
    func beginPushToTalk()
    func endPushToTalk()
}

@MainActor
protocol SpeechTranscribing: AnyObject {
    func start() async throws
    func stop() async throws -> String
    func cancel()
}

@MainActor
protocol TextInjecting: AnyObject {
    func captureTarget() throws -> TextInsertionTarget
    func insert(_ text: String, into target: TextInsertionTarget) async throws
    func discard(_ target: TextInsertionTarget)
}

@MainActor
protocol PermissionManaging: AnyObject {
    func snapshot() -> PermissionSnapshot
    func request(_ permission: AppPermission) async -> PermissionStatus
}
