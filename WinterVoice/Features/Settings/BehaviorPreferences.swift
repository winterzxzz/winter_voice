import Foundation

/// Persisted Behavior-section toggles, shared between the Settings screen and
/// the dictation pipeline.
@MainActor
final class BehaviorPreferences: ObservableObject, DictationBehaviorProviding {
    /// Chime when recording starts and stops.
    @Published var playsRecordingSounds: Bool {
        didSet { defaults.set(playsRecordingSounds, forKey: Self.recordingSoundsKey) }
    }
    /// Mute the speakers while recording so the mic stays clean.
    @Published var pausesOtherAudio: Bool {
        didSet { defaults.set(pausesOtherAudio, forKey: Self.pauseOtherAudioKey) }
    }
    /// Put transcripts on the clipboard instead of typing them into the
    /// focused field.
    @Published var copiesInsteadOfInserting: Bool {
        didSet { defaults.set(copiesInsteadOfInserting, forKey: Self.copyInsteadKey) }
    }

    private static let recordingSoundsKey = "behavior.recordingSounds"
    private static let pauseOtherAudioKey = "behavior.pauseOtherAudio"
    private static let copyInsteadKey = "behavior.copyInsteadOfInserting"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        playsRecordingSounds = defaults.object(forKey: Self.recordingSoundsKey) as? Bool ?? true
        pausesOtherAudio = defaults.object(forKey: Self.pauseOtherAudioKey) as? Bool ?? false
        copiesInsteadOfInserting = defaults.object(forKey: Self.copyInsteadKey) as? Bool ?? false
    }
}
