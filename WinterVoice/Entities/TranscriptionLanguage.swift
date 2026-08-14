import Foundation

/// A transcription language shared by local whisper and cloud providers.
/// The selection is stored as an ISO 639-1 code (what whisper.cpp and
/// OpenAI-compatible endpoints both accept); a `nil` selection means
/// auto-detect.
struct TranscriptionLanguage: Identifiable, Equatable, Sendable {
    let code: String
    let name: String
    var id: String { code }

    /// Languages surfaced in the picker — Vietnamese and English first (the
    /// app's primary audiences), then the reference set alphabetically.
    static let all: [TranscriptionLanguage] = [
        .init(code: "vi", name: "Vietnamese"),
        .init(code: "en", name: "English"),
        .init(code: "ar", name: "Arabic"),
        .init(code: "ca", name: "Catalan"),
        .init(code: "zh", name: "Chinese"),
        .init(code: "cs", name: "Czech"),
        .init(code: "da", name: "Danish"),
        .init(code: "nl", name: "Dutch"),
        .init(code: "fi", name: "Finnish"),
        .init(code: "fr", name: "French"),
        .init(code: "de", name: "German"),
        .init(code: "el", name: "Greek"),
        .init(code: "he", name: "Hebrew"),
        .init(code: "hi", name: "Hindi"),
        .init(code: "hu", name: "Hungarian"),
        .init(code: "id", name: "Indonesian"),
        .init(code: "it", name: "Italian"),
        .init(code: "ja", name: "Japanese"),
        .init(code: "ko", name: "Korean"),
        .init(code: "no", name: "Norwegian"),
        .init(code: "pl", name: "Polish"),
        .init(code: "pt", name: "Portuguese"),
        .init(code: "ro", name: "Romanian"),
        .init(code: "ru", name: "Russian"),
        .init(code: "es", name: "Spanish"),
        .init(code: "sv", name: "Swedish"),
        .init(code: "th", name: "Thai"),
        .init(code: "tr", name: "Turkish"),
        .init(code: "uk", name: "Ukrainian"),
    ]

    static func name(forCode code: String?) -> String? {
        guard let code else { return nil }
        return all.first { $0.code == code }?.name
    }

    static func isKnown(_ code: String) -> Bool {
        all.contains { $0.code == code }
    }
}
