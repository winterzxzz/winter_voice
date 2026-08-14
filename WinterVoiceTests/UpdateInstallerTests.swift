import Foundation
import XCTest
@testable import WinterVoice

@MainActor
final class UpdateInstallerTests: XCTestCase {
    // MARK: hdiutil plist parsing

    func testMountPointParsedFromAttachPlist() throws {
        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>system-entities</key>
            <array>
                <dict>
                    <key>content-hint</key>
                    <string>GUID_partition_scheme</string>
                    <key>dev-entry</key>
                    <string>/dev/disk4</string>
                </dict>
                <dict>
                    <key>dev-entry</key>
                    <string>/dev/disk4s1</string>
                    <key>mount-point</key>
                    <string>/Volumes/WinterVoice</string>
                </dict>
            </array>
        </dict>
        </plist>
        """
        let mountPoint = DMGUpdateInstaller.mountPoint(fromAttachPlist: Data(plist.utf8))
        XCTAssertEqual(mountPoint, "/Volumes/WinterVoice")
    }

    func testMountPointNilForGarbageOutput() {
        XCTAssertNil(DMGUpdateInstaller.mountPoint(fromAttachPlist: Data("not a plist".utf8)))
    }

    // MARK: Staged bundle validation

    private func info(bundleID: String = "com.winterzxzz.WinterVoice", version: String = "0.4.0") -> [String: Any] {
        ["CFBundleIdentifier": bundleID, "CFBundleShortVersionString": version]
    }

    func testValidationAcceptsMatchingBundle() {
        XCTAssertNil(DMGUpdateInstaller.validationProblem(
            info: info(), expectedBundleID: "com.winterzxzz.WinterVoice", expectedVersion: "0.4.0"
        ))
    }

    func testValidationRejectsForeignBundleIdentifier() {
        let problem = DMGUpdateInstaller.validationProblem(
            info: info(bundleID: "com.evil.Imposter"),
            expectedBundleID: "com.winterzxzz.WinterVoice", expectedVersion: "0.4.0"
        )
        XCTAssertEqual(problem, "it is com.evil.Imposter, not com.winterzxzz.WinterVoice")
    }

    func testValidationRejectsVersionMismatch() {
        let problem = DMGUpdateInstaller.validationProblem(
            info: info(version: "0.3.9"),
            expectedBundleID: "com.winterzxzz.WinterVoice", expectedVersion: "0.4.0"
        )
        XCTAssertEqual(problem, "it is version 0.3.9, not 0.4.0")
    }

    // MARK: Install preconditions

    func testInstallBlockerRejectsNonAppAndTranslocatedPaths() {
        XCTAssertNotNil(DMGUpdateInstaller.installBlocker(
            forBundleAt: URL(fileURLWithPath: "/usr/local/bin/wintervoice")
        ))
        XCTAssertNotNil(DMGUpdateInstaller.installBlocker(
            forBundleAt: URL(fileURLWithPath: "/private/var/folders/x/AppTranslocation/ABC/d/WinterVoice.app")
        ))
    }

    func testInstallBlockerAllowsWritableAppBundle() throws {
        let parent = FileManager.default.temporaryDirectory
            .appendingPathComponent("UpdateInstallerTests-\(UUID().uuidString)", isDirectory: true)
        let bundle = parent.appendingPathComponent("WinterVoice.app", isDirectory: true)
        try FileManager.default.createDirectory(at: bundle, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: parent) }
        XCTAssertNil(DMGUpdateInstaller.installBlocker(forBundleAt: bundle))
    }

    // MARK: Relaunch script

    func testRelaunchScriptWaitsOnPidAndQuotesPath() {
        let script = DMGUpdateInstaller.relaunchShellScript(
            pid: 123, appPath: "/Applications/Winter's Voice.app"
        )
        XCTAssertTrue(script.contains("/bin/kill -0 123"))
        XCTAssertTrue(script.contains("/usr/bin/open '/Applications/Winter'\\''s Voice.app'"))
    }

    // MARK: End to end against a real disk image

    /// Full pipeline minus the network: builds a signed dummy app, packs it
    /// into a real .dmg, and lets the installer mount, verify, and swap it
    /// over a fake installed bundle.
    func testEndToEndInstallFromLocalImage() async throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory
            .appendingPathComponent("UpdateInstallerE2E-\(UUID().uuidString)", isDirectory: true)
        addTeardownBlock { try? fileManager.removeItem(at: root) }

        func writeDummyApp(at bundle: URL, version: String) throws {
            let contents = bundle.appendingPathComponent("Contents", isDirectory: true)
            try fileManager.createDirectory(
                at: contents.appendingPathComponent("MacOS"), withIntermediateDirectories: true
            )
            let info: [String: Any] = [
                "CFBundleIdentifier": "com.winterzxzz.UpdateInstallerE2E",
                "CFBundleShortVersionString": version,
                "CFBundleExecutable": "Dummy",
                "CFBundlePackageType": "APPL",
            ]
            try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
                .write(to: contents.appendingPathComponent("Info.plist"))
            try fileManager.copyItem(
                at: URL(fileURLWithPath: "/bin/ls"),
                to: contents.appendingPathComponent("MacOS/Dummy")
            )
        }

        func run(_ tool: String, _ arguments: [String]) throws {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: tool)
            process.arguments = arguments
            process.standardOutput = Pipe()
            process.standardError = Pipe()
            try process.run()
            process.waitUntilExit()
            XCTAssertEqual(process.terminationStatus, 0, "\(tool) \(arguments) failed")
        }

        // The release: a signed 9.9.9 bundle inside a compressed image.
        let imageSource = root.appendingPathComponent("image-source", isDirectory: true)
        try writeDummyApp(at: imageSource.appendingPathComponent("Dummy.app"), version: "9.9.9")
        try run("/usr/bin/codesign", ["--force", "--sign", "-", imageSource.appendingPathComponent("Dummy.app").path])
        let dmg = root.appendingPathComponent("update.dmg")
        try run("/usr/bin/hdiutil", ["create", "-volname", "DummyUpdate", "-srcfolder", imageSource.path, "-format", "UDZO", "-quiet", dmg.path])

        // The "installed" copy the swap must replace.
        let installed = root.appendingPathComponent("Applications/Dummy.app", isDirectory: true)
        try writeDummyApp(at: installed, version: "1.0.0")

        let installer = DMGUpdateInstaller(
            bundleURL: installed,
            bundleIdentifier: "com.winterzxzz.UpdateInstallerE2E",
            currentVersion: "1.0.0"
        )
        let update = AvailableUpdate(
            version: "9.9.9", highlights: [],
            downloadURL: dmg, releaseURL: URL(string: "https://example.com/release")!
        )
        let phases = PhaseLog()
        try await installer.install(update) { phases.record($0) }

        let swappedInfo = NSDictionary(
            contentsOf: installed.appendingPathComponent("Contents/Info.plist")
        ) as? [String: Any]
        XCTAssertEqual(swappedInfo?["CFBundleShortVersionString"] as? String, "9.9.9")
        XCTAssertTrue(phases.entries.contains(.installing))
        XCTAssertNil(DMGUpdateInstaller.installBlocker(forBundleAt: installed))
    }

    // MARK: Controller install flow

    private func makeUpdate() -> AvailableUpdate {
        AvailableUpdate(
            version: "0.4.0",
            highlights: [],
            downloadURL: URL(string: "https://example.com/WinterVoice.dmg"),
            releaseURL: URL(string: "https://example.com/release")!
        )
    }

    private func makeController(
        installer: UpdateInstallerStub,
        openURL: @escaping (URL) -> Void = { _ in }
    ) throws -> UpdateController {
        let suite = "UpdateInstallerTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        return UpdateController(
            checker: UpdateCheckingNoop(), installer: installer,
            defaults: defaults, openURL: openURL, now: Date.init
        )
    }

    private func drainMainQueue() async {
        for _ in 0..<4 { await Task.yield() }
    }

    func testSuccessfulInstallProgressesAndRelaunches() async throws {
        let installer = UpdateInstallerStub(result: .success(()))
        let controller = try makeController(installer: installer)

        controller.install(makeUpdate())
        XCTAssertEqual(controller.state, .downloading(makeUpdate(), 0))
        await drainMainQueue()

        XCTAssertEqual(controller.state, .installing(makeUpdate()))
        XCTAssertEqual(installer.installedVersions, ["0.4.0"])
        XCTAssertTrue(installer.didRelaunch)
    }

    func testFailedInstallSurfacesMessageAndKeepsAppRunning() async throws {
        let installer = UpdateInstallerStub(result: .failure(.badDownload("the connection was interrupted")))
        let controller = try makeController(installer: installer)

        controller.install(makeUpdate())
        await drainMainQueue()

        XCTAssertEqual(controller.state, .installFailed(
            makeUpdate(), "The download failed: the connection was interrupted."
        ))
        XCTAssertFalse(installer.didRelaunch)
    }

    func testBlockedInstallFallsBackToBrowserDownload() async throws {
        let installer = UpdateInstallerStub(result: .success(()), blocker: "running translocated")
        var opened: [URL] = []
        let controller = try makeController(installer: installer) { opened.append($0) }

        controller.install(makeUpdate())
        await drainMainQueue()

        XCTAssertEqual(opened.map(\.lastPathComponent), ["WinterVoice.dmg"])
        XCTAssertTrue(installer.installedVersions.isEmpty)
    }

    func testChecksAndReinstallsAreIgnoredWhileInstalling() async throws {
        let installer = UpdateInstallerStub(result: .success(()), holdUntilReleased: true)
        let controller = try makeController(installer: installer)

        controller.install(makeUpdate())
        await drainMainQueue()
        controller.install(makeUpdate())
        controller.checkNow()
        XCTAssertEqual(controller.state, .downloading(makeUpdate(), 0))
        XCTAssertEqual(installer.installedVersions, ["0.4.0"])

        installer.release()
        await drainMainQueue()
        XCTAssertEqual(controller.state, .installing(makeUpdate()))
    }
}

@MainActor
private final class UpdateInstallerStub: UpdateInstalling, @unchecked Sendable {
    private let result: Result<Void, UpdateInstallError>
    private let blocker: String?
    private let holdUntilReleased: Bool
    private var releaseContinuation: CheckedContinuation<Void, Never>?
    private(set) var installedVersions: [String] = []
    private(set) var didRelaunch = false

    init(
        result: Result<Void, UpdateInstallError>,
        blocker: String? = nil,
        holdUntilReleased: Bool = false
    ) {
        self.result = result
        self.blocker = blocker
        self.holdUntilReleased = holdUntilReleased
    }

    func installBlocker() -> String? { blocker }

    func install(_ update: AvailableUpdate, onPhase: @escaping @Sendable (UpdateInstallPhase) -> Void) async throws {
        installedVersions.append(update.version)
        if holdUntilReleased {
            await withCheckedContinuation { releaseContinuation = $0 }
        }
        try result.get()
    }

    func relaunchAndTerminate() {
        didRelaunch = true
    }

    func release() {
        releaseContinuation?.resume()
        releaseContinuation = nil
    }
}

@MainActor
private final class UpdateCheckingNoop: UpdateChecking {
    func fetchAvailableUpdate() async throws -> AvailableUpdate? { nil }
}

/// Records install phases synchronously, so assertions after `install`
/// returns see every callback with no task-scheduling race.
private final class PhaseLog: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [UpdateInstallPhase] = []

    var entries: [UpdateInstallPhase] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func record(_ phase: UpdateInstallPhase) {
        lock.lock()
        defer { lock.unlock() }
        storage.append(phase)
    }
}
