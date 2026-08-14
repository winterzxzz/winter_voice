import AppKit
import AudioToolbox
import Combine
import CoreAudio

/// Behavior-section session feedback: plays the start/stop chimes and mutes
/// the system output while recording, driven by the dictation state relay.
@MainActor
final class RecordingSessionFeedback {
    private let preferences: BehaviorPreferences
    private let muter = SystemOutputMuter()
    private var previousState: DictationState = .idle
    private var cancellable: AnyCancellable?
    private var muteTask: Task<Void, Never>?

    // NSSound caches by name; stop() before play() so rapid sessions retrigger.
    private let startSound = NSSound(named: "Tink")
    private let stopSound = NSSound(named: "Pop")

    init(relay: DictationStateRelay, preferences: BehaviorPreferences) {
        self.preferences = preferences
        cancellable = relay.$state.sink { [weak self] state in
            self?.handle(state)
        }
    }

    private func handle(_ state: DictationState) {
        defer { previousState = state }
        guard state != previousState else { return }
        if state == .recording {
            if preferences.playsRecordingSounds { play(startSound) }
            if preferences.pausesOtherAudio {
                // Give the start chime a beat to be heard before the output
                // mutes; a cancelled task leaves the output untouched.
                let delayForChime = preferences.playsRecordingSounds
                muteTask = Task { [muter] in
                    if delayForChime { try? await Task.sleep(for: .milliseconds(280)) }
                    guard !Task.isCancelled else { return }
                    muter.mute()
                }
            }
        } else {
            muteTask?.cancel()
            muteTask = nil
            muter.restore()
            // Only a real recording→processing handoff chimes; failures and
            // cancels stay silent.
            if previousState == .recording, state == .processing,
               preferences.playsRecordingSounds {
                play(stopSound)
            }
        }
    }

    private func play(_ sound: NSSound?) {
        guard let sound else { return }
        sound.stop()
        sound.play()
    }
}

/// Mutes the default output device and restores its prior state afterwards.
/// Devices without a settable master mute fall back to zeroing the volume.
@MainActor
final class SystemOutputMuter {
    private var restoreAction: (() -> Void)?

    func mute() {
        guard restoreAction == nil, let device = Self.defaultOutputDevice() else { return }
        var muteAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        if Self.isSettable(device, &muteAddress),
           let previous: UInt32 = Self.read(device, &muteAddress) {
            if Self.write(device, &muteAddress, value: UInt32(1)) {
                restoreAction = {
                    var address = muteAddress
                    _ = Self.write(device, &address, value: previous)
                }
            }
            return
        }
        var volumeAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        if Self.isSettable(device, &volumeAddress),
           let previous: Float32 = Self.read(device, &volumeAddress),
           Self.write(device, &volumeAddress, value: Float32(0)) {
            restoreAction = {
                var address = volumeAddress
                _ = Self.write(device, &address, value: previous)
            }
        }
    }

    func restore() {
        restoreAction?()
        restoreAction = nil
    }

    private static func defaultOutputDevice() -> AudioDeviceID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var device = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device
        )
        guard status == noErr, device != kAudioObjectUnknown else { return nil }
        return device
    }

    private static func isSettable(
        _ device: AudioDeviceID, _ address: inout AudioObjectPropertyAddress
    ) -> Bool {
        guard AudioObjectHasProperty(device, &address) else { return false }
        var settable = DarwinBoolean(false)
        return AudioObjectIsPropertySettable(device, &address, &settable) == noErr
            && settable.boolValue
    }

    private static func read<Value>(
        _ device: AudioDeviceID, _ address: inout AudioObjectPropertyAddress
    ) -> Value? {
        var size = UInt32(MemoryLayout<Value>.size)
        let value = UnsafeMutablePointer<Value>.allocate(capacity: 1)
        defer { value.deallocate() }
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, value) == noErr else {
            return nil
        }
        return value.pointee
    }

    private static func write<Value>(
        _ device: AudioDeviceID, _ address: inout AudioObjectPropertyAddress, value: Value
    ) -> Bool {
        var value = value
        return AudioObjectSetPropertyData(
            device, &address, 0, nil, UInt32(MemoryLayout<Value>.size), &value
        ) == noErr
    }
}
