import AppKit
import AVFoundation

@MainActor
final class SystemPermissionManager: PermissionManaging {
    func snapshot() -> PermissionSnapshot {
        PermissionSnapshot(
            microphone: Self.map(AVCaptureDevice.authorizationStatus(for: .audio)),
            inputMonitoring: CGPreflightListenEventAccess() ? .authorized : .denied,
            accessibility: AXIsProcessTrusted() ? .authorized : .denied
        )
    }

    func request(_ permission: AppPermission) async -> PermissionStatus {
        switch permission {
        case .microphone:
            _ = await AVCaptureDevice.requestAccess(for: .audio)
        case .inputMonitoring:
            _ = CGRequestListenEventAccess()
        case .accessibility:
            AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
        }
        return snapshot()[permission]
    }

    private static func map(_ status: AVAuthorizationStatus) -> PermissionStatus {
        switch status {
        case .notDetermined: .notDetermined
        case .authorized: .authorized
        case .denied: .denied
        case .restricted: .restricted
        @unknown default: .restricted
        }
    }
}
