import Foundation

enum ProviderMode: String, CaseIterable, Codable, Sendable {
    case local
    case remote

    var title: String { self == .local ? "Local Model" : "Remote API" }
}

struct RemoteProviderConfiguration: Equatable, Codable, Sendable {
    var baseURL = ""
    var model = ""
    var language = ""

    var normalizedLanguage: String? {
        let value = language.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
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
            return "Remote transcription is configured. Hold Right Option to record, then release to transcribe and insert text."
        }
        return readiness.detail
    }

    var privacySummary: String {
        switch (mode, isReady) {
        case (.remote, true):
            "Audio is sent only to your configured remote endpoint when you dictate. Optional API keys remain in Keychain, unauthenticated endpoints receive no Authorization header, and audio or transcripts are not logged."
        case (.remote, false):
            "Remote mode is not ready, so dictation attempts do not record or send audio."
        case (.local, _):
            "Local mode is not ready, so dictation attempts do not record or send audio. No supported downloadable model or approved runtime is available yet."
        }
    }
}
