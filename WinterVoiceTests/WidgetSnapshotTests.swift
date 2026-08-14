import AppKit
import SwiftUI
import XCTest
@testable import WinterVoice

/// Renders every widget state to PNGs so layout changes can be reviewed
/// without launching the app. Output lands in the directory named by the
/// WIDGET_SNAPSHOT_DIR environment variable; the test is skipped when the
/// variable is absent (normal CI runs).
@MainActor
final class WidgetSnapshotTests: XCTestCase {
    func testRenderWidgetStates() throws {
        guard let path = ProcessInfo.processInfo.environment["WIDGET_SNAPSHOT_DIR"] else {
            throw XCTSkip("WIDGET_SNAPSHOT_DIR not set")
        }
        let outputDirectory = URL(fileURLWithPath: path, isDirectory: true)
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

        let relay = DictationStateRelay()
        let presenter = DictationPresenter(
            interactor: SnapshotInteractorFake(),
            relay: relay,
            hotkeyRelay: HotkeyHealthRelay(),
            permissionManager: SnapshotPermissionFake(),
            router: AppRouter()
        )
        let meter = AudioLevelMeter()
        meter.update(0.8)

        func snap(_ name: String, style: WidgetStyle) throws {
            let view = ZStack {
                Color(red: 0.35, green: 0.42, blue: 0.55)
                RecordingPanelView(presenter: presenter, levelMeter: meter, style: style)
                    .padding(16)
            }
            .fixedSize()
            let renderer = ImageRenderer(content: view)
            renderer.scale = 2
            guard let image = renderer.nsImage,
                  let tiff = image.tiffRepresentation,
                  let rep = NSBitmapImageRep(data: tiff),
                  let png = rep.representation(using: .png, properties: [:]) else {
                XCTFail("Could not render \(name)")
                return
            }
            let url = outputDirectory.appendingPathComponent("\(name).png")
            try png.write(to: url)
            print("SNAPSHOT \(name): \(Int(image.size.width))x\(Int(image.size.height))")
        }

        relay.publish(.idle)
        try snap("idle-labeled", style: .labeled)
        try snap("idle-icon", style: .icon)
        try snap("idle-minimal", style: .minimal)

        relay.publish(.recording)
        try snap("recording", style: .labeled)

        relay.publish(.failed(DictationFailure(
            message: "Microphone access denied.",
            recovery: "Enable it in System Settings."
        )))
        try snap("error-short", style: .labeled)

        relay.publish(.failed(DictationFailure(
            message: "The transcription service could not be reached because the network connection appears to be offline right now.",
            recovery: "Check your internet connection, verify the server URL in Settings, and then try dictating again."
        )))
        try snap("error-long", style: .labeled)
    }
}

@MainActor
private final class SnapshotInteractorFake: DictationInteracting {
    func beginPushToTalk() {}
    func endPushToTalk() {}
    func togglePushToTalk() {}
}

@MainActor
private final class SnapshotPermissionFake: PermissionManaging {
    func snapshot() -> PermissionSnapshot {
        PermissionSnapshot(microphone: .authorized, inputMonitoring: .authorized, accessibility: .authorized)
    }

    func request(_ permission: AppPermission) async -> PermissionStatus { .authorized }
}
