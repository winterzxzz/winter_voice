import Combine
import CoreAudio
import Foundation

/// Software gain applied to captured samples before transcription — the
/// reference "Mic boost" Off/2×/4×/6×/8× control.
enum MicBoost: String, CaseIterable, Sendable {
    case off, x2, x4, x6, x8

    var gain: Float {
        switch self {
        case .off: 1
        case .x2: 2
        case .x4: 4
        case .x6: 6
        case .x8: 8
        }
    }

    var label: String {
        switch self {
        case .off: "Off"
        case .x2: "2\u{00D7}"
        case .x4: "4\u{00D7}"
        case .x6: "6\u{00D7}"
        case .x8: "8\u{00D7}"
        }
    }
}

/// User-selected capture hardware and gain: the preferred microphone, a
/// backup used when the preferred one disconnects, and mic boost. `nil`
/// device UIDs mean "follow the macOS system default". Keeps the connected
/// device list fresh by listening for HAL topology changes.
@MainActor
final class MicrophonePreferences: ObservableObject {
    @Published var preferredDeviceUID: String? {
        didSet {
            defaults.set(preferredDeviceUID, forKey: Self.preferredKey)
            refreshDevices()
        }
    }
    @Published var backupDeviceUID: String? {
        didSet {
            defaults.set(backupDeviceUID, forKey: Self.backupKey)
            refreshDevices()
        }
    }
    @Published var boost: MicBoost {
        didSet { defaults.set(boost.rawValue, forKey: Self.boostKey) }
    }
    @Published private(set) var availableDevices: [AudioInputDevice] = []
    /// The device recording would use right now, after fallback resolution.
    @Published private(set) var activeDevice: AudioInputDevice?

    private static let preferredKey = "microphone.preferredUID"
    private static let backupKey = "microphone.backupUID"
    private static let boostKey = "microphone.boost"
    private let defaults: UserDefaults
    private var topologyListener: AudioObjectPropertyListenerBlock?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        preferredDeviceUID = defaults.string(forKey: Self.preferredKey)
        backupDeviceUID = defaults.string(forKey: Self.backupKey)
        boost = defaults.string(forKey: Self.boostKey)
            .flatMap(MicBoost.init(rawValue:)) ?? .off
        refreshDevices()
        installTopologyListener()
    }

    /// Re-reads the connected input devices and the resolved active device.
    func refreshDevices() {
        availableDevices = AudioInputDeviceList.all()
        activeDevice = resolveCaptureDevice()
    }

    /// The device recording should pin: the preferred device when connected,
    /// otherwise the backup, otherwise whatever macOS calls default input.
    func resolveCaptureDevice() -> AudioInputDevice? {
        let connected = AudioInputDeviceList.all()
        if let preferredDeviceUID,
           let preferred = connected.first(where: { $0.uid == preferredDeviceUID }) {
            return preferred
        }
        if let backupDeviceUID,
           let backup = connected.first(where: { $0.uid == backupDeviceUID }) {
            return backup
        }
        return AudioInputDeviceList.systemDefault()
    }

    func device(forUID uid: String?) -> AudioInputDevice? {
        guard let uid else { return nil }
        return availableDevices.first { $0.uid == uid }
    }

    private func installTopologyListener() {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        // HAL blocks must be @Sendable with Sendable-only captures even when
        // dispatched to main — a MainActor-inferred closure traps off-thread.
        let listener: AudioObjectPropertyListenerBlock = { @Sendable [weak self] _, _ in
            Task { @MainActor in self?.refreshDevices() }
        }
        topologyListener = listener
        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            DispatchQueue.main,
            listener
        )
    }
}
