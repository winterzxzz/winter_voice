import Foundation
import Speech

@MainActor
protocol AppShellInteracting: AnyObject {
    func transcriptionCapability() -> TranscriptionCapability
}

@MainActor
final class AppShellInteractor: AppShellInteracting {
    func transcriptionCapability() -> TranscriptionCapability {
        let recognizer = SFSpeechRecognizer()
        let locale = recognizer?.locale ?? .current
        let displayName = Locale.current.localizedString(forIdentifier: locale.identifier)
            ?? locale.localizedString(forIdentifier: locale.identifier)
            ?? locale.identifier

        return TranscriptionCapability(
            providerName: "Apple Speech",
            modeName: "On-device",
            localeIdentifier: locale.identifier,
            localeDisplayName: displayName,
            isRecognizerAvailable: recognizer?.isAvailable ?? false,
            supportsOnDeviceRecognition: recognizer?.supportsOnDeviceRecognition ?? false
        )
    }
}
