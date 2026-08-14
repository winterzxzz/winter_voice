import Foundation

enum ProviderMode: String, CaseIterable, Codable, Sendable {
    case local
    case remote

    var title: String { self == .local ? "Local Model" : "Remote API" }
}

struct RemoteProviderConfiguration: Equatable, Codable, Sendable {
    var baseURL = ""
    var model = ""
}

enum ProviderReadiness: Equatable, Sendable {
    case ready(String)
    case unavailable(String)

    var isReady: Bool {
        if case .ready = self { return true }
        return false
    }

    var detail: String {
        switch self {
        case .ready(let detail), .unavailable(let detail): detail
        }
    }
}

struct ProviderStatus: Equatable, Sendable {
    let mode: ProviderMode
    let readiness: ProviderReadiness

    var title: String { mode.title }
    var isReady: Bool { readiness.isReady }
    var stateLabel: String { isReady ? "Ready" : "Not ready" }

    var overviewSummary: String {
        if isReady {
            return "Transcription is ready. Hold the configured push-to-talk key, then release to transcribe and insert text."
        }
        return readiness.detail
    }

    var privacySummary: String {
        switch (mode, isReady) {
        case (.remote, true):
            "Audio is sent only to your configured remote endpoint when you dictate. Optional API keys are stored locally on this Mac, unauthenticated endpoints receive no Authorization header, and audio or transcripts are not logged."
        case (.remote, false):
            "Remote mode is not ready, so dictation attempts do not record or send audio."
        case (.local, true):
            "Audio is transcribed privately on this Mac with the selected whisper.cpp model and is never sent to a remote provider."
        case (.local, false):
            "Local mode is not ready, so dictation attempts do not record or send audio."
        }
    }
}
