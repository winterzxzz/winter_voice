import AppKit

/// Puts the transcript on the general pasteboard, without the concealed and
/// transient marks the injection path uses — in copy mode the user wants the
/// text to survive in clipboard managers until they paste it.
@MainActor
final class SystemTranscriptCopier: TranscriptCopying {
    func copy(_ text: String) -> Bool {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        return pasteboard.setString(text, forType: .string)
    }
}
