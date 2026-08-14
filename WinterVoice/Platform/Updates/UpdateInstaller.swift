import AppKit
import Foundation

/// Progress milestones of an in-place update, for driving UI state.
enum UpdateInstallPhase: Equatable, Sendable {
    /// Fraction of the image downloaded, 0...1; stays at 0 when the server
    /// sends no Content-Length.
    case downloading(Double)
    /// Image mounted and the new bundle is being verified and swapped in.
    case installing
}

enum UpdateInstallError: LocalizedError, Equatable {
    case noAsset
    case badDownload(String)
    case badImage(String)
    case validationFailed(String)
    case swapFailed(String)

    var errorDescription: String? {
        switch self {
        case .noAsset: "This release has no .dmg to install."
        case .badDownload(let detail): "The download failed: \(detail)."
        case .badImage(let detail): "The update image could not be opened: \(detail)."
        case .validationFailed(let detail): "The downloaded app failed verification: \(detail)."
        case .swapFailed(let detail): "The installed app could not be replaced: \(detail)."
        }
    }
}

protocol UpdateInstalling: Sendable {
    /// Why an in-place install is impossible right now (translocated bundle,
    /// unwritable install location, dev build), or nil when it can proceed.
    @MainActor func installBlocker() -> String?
    /// Downloads the release image and swaps the new bundle into the running
    /// app's location. Returns once the new version is fully on disk; the
    /// caller then decides when to relaunch.
    func install(_ update: AvailableUpdate, onPhase: @escaping @Sendable (UpdateInstallPhase) -> Void) async throws
    /// Spawns a watcher that reopens the (now replaced) bundle after this
    /// process exits, then terminates the app.
    @MainActor func relaunchAndTerminate()
}

/// Installs a GitHub release `.dmg` over the running app: silent mount, copy
/// to a staging folder, identity + signature verification, then an atomic
/// swap with rollback. Downloading in-process (not via a browser) also means
/// no quarantine attribute, so the relaunched build skips the Gatekeeper
/// "unidentified developer" dance an ad-hoc-signed download would hit.
final class DMGUpdateInstaller: UpdateInstalling {
    private let bundleURL: URL
    private let bundleIdentifier: String
    private let currentVersion: String

    init(
        bundleURL: URL = Bundle.main.bundleURL,
        bundleIdentifier: String = Bundle.main.bundleIdentifier ?? "com.winterzxzz.WinterVoice",
        currentVersion: String = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    ) {
        self.bundleURL = bundleURL
        self.bundleIdentifier = bundleIdentifier
        self.currentVersion = currentVersion
    }

    @MainActor
    func installBlocker() -> String? {
        Self.installBlocker(forBundleAt: bundleURL)
    }

    func install(_ update: AvailableUpdate, onPhase: @escaping @Sendable (UpdateInstallPhase) -> Void) async throws {
        guard let downloadURL = update.downloadURL else { throw UpdateInstallError.noAsset }

        let workDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("WinterVoice-Update-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)

        do {
            let dmg = workDir.appendingPathComponent("update.dmg")
            try await download(from: downloadURL, to: dmg, onPhase: onPhase)
            onPhase(.installing)
            let staged = try await stageBundle(fromImage: dmg, in: workDir, expectedVersion: update.version)
            try swapInstalledBundle(with: staged, workDir: workDir)
        } catch {
            try? FileManager.default.removeItem(at: workDir)
            throw error
        }
        // Keep workDir: it now holds the previous bundle (moved aside during
        // the swap) until the temp directory is purged by the system.
    }

    @MainActor
    func relaunchAndTerminate() {
        let script = Self.relaunchShellScript(
            pid: ProcessInfo.processInfo.processIdentifier,
            appPath: bundleURL.path
        )
        let watcher = Process()
        watcher.executableURL = URL(fileURLWithPath: "/bin/sh")
        watcher.arguments = ["-c", script]
        try? watcher.run()
        NSApp.terminate(nil)
    }

    // MARK: Download

    private func download(
        from url: URL,
        to destination: URL,
        onPhase: @escaping @Sendable (UpdateInstallPhase) -> Void
    ) async throws {
        var request = URLRequest(url: url)
        request.setValue("WinterVoice/\(currentVersion)", forHTTPHeaderField: "User-Agent")
        let bytes: URLSession.AsyncBytes
        let response: URLResponse
        do {
            (bytes, response) = try await URLSession.shared.bytes(for: request)
        } catch {
            throw UpdateInstallError.badDownload(error.localizedDescription)
        }
        // Non-HTTP responses (file URLs in tests) carry no status to check.
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw UpdateInstallError.badDownload("the server rejected the request")
        }

        let expected = response.expectedContentLength
        guard FileManager.default.createFile(atPath: destination.path, contents: nil) else {
            throw UpdateInstallError.badDownload("could not create a temporary file")
        }
        let handle = try FileHandle(forWritingTo: destination)
        defer { try? handle.close() }

        let chunkSize = 4 << 20
        var buffer = Data(capacity: chunkSize)
        var written: Int64 = 0
        var lastReported = 0.0
        do {
            for try await byte in bytes {
                buffer.append(byte)
                if buffer.count >= chunkSize {
                    try handle.write(contentsOf: buffer)
                    written += Int64(buffer.count)
                    buffer.removeAll(keepingCapacity: true)
                    if expected > 0 {
                        let fraction = min(Double(written) / Double(expected), 1)
                        if fraction - lastReported >= 0.01 {
                            lastReported = fraction
                            onPhase(.downloading(fraction))
                        }
                    }
                }
            }
            try handle.write(contentsOf: buffer)
            written += Int64(buffer.count)
        } catch let error as UpdateInstallError {
            throw error
        } catch {
            throw UpdateInstallError.badDownload("the connection was interrupted")
        }
        if expected > 0, written < expected {
            throw UpdateInstallError.badDownload("the connection was interrupted")
        }
    }

    // MARK: Stage and verify

    /// Mounts the image, copies its app bundle into `workDir`, and verifies
    /// identity, version, and code-signature integrity before returning it.
    private func stageBundle(fromImage dmg: URL, in workDir: URL, expectedVersion: String) async throws -> URL {
        let attachOutput: Data
        do {
            attachOutput = try await Self.run("/usr/bin/hdiutil", [
                "attach", dmg.path, "-nobrowse", "-noautoopen", "-noverify", "-readonly", "-plist",
            ])
        } catch {
            throw UpdateInstallError.badImage("hdiutil could not mount it")
        }
        guard let mountPoint = Self.mountPoint(fromAttachPlist: attachOutput) else {
            throw UpdateInstallError.badImage("no mounted volume was reported")
        }

        var staged: URL?
        var failure: Error?
        do {
            let apps = try FileManager.default
                .contentsOfDirectory(at: URL(fileURLWithPath: mountPoint), includingPropertiesForKeys: nil)
                .filter { $0.pathExtension == "app" }
            guard let source = apps.first else {
                throw UpdateInstallError.badImage("it contains no app bundle")
            }
            let target = workDir.appendingPathComponent(source.lastPathComponent, isDirectory: true)
            try await Self.run("/usr/bin/ditto", [source.path, target.path])
            staged = target
        } catch {
            failure = error
        }
        _ = try? await Self.run("/usr/bin/hdiutil", ["detach", mountPoint, "-force"])
        if let failure { throw failure }
        guard let staged else { throw UpdateInstallError.badImage("copying out of the image failed") }

        let infoURL = staged.appendingPathComponent("Contents/Info.plist")
        guard let infoData = try? Data(contentsOf: infoURL),
              let info = try? PropertyListSerialization.propertyList(from: infoData, format: nil) as? [String: Any]
        else {
            throw UpdateInstallError.validationFailed("its Info.plist is unreadable")
        }
        if let problem = Self.validationProblem(
            info: info, expectedBundleID: bundleIdentifier, expectedVersion: expectedVersion
        ) {
            throw UpdateInstallError.validationFailed(problem)
        }
        do {
            try await Self.run("/usr/bin/codesign", ["--verify", "--deep", "--strict", staged.path])
        } catch {
            throw UpdateInstallError.validationFailed("its code signature is broken")
        }
        return staged
    }

    // MARK: Swap

    /// Replaces the running bundle with `staged`: old bundle moves into
    /// `workDir`, new one moves into place, and a failed second step rolls
    /// the old bundle back so the install never ends app-less.
    private func swapInstalledBundle(with staged: URL, workDir: URL) throws {
        let fileManager = FileManager.default
        let previous = workDir.appendingPathComponent("previous.app", isDirectory: true)
        do {
            try fileManager.moveItem(at: bundleURL, to: previous)
        } catch {
            throw UpdateInstallError.swapFailed("the current app could not be moved aside")
        }
        do {
            try fileManager.moveItem(at: staged, to: bundleURL)
        } catch {
            try? fileManager.moveItem(at: previous, to: bundleURL)
            throw UpdateInstallError.swapFailed("the new app could not be moved into place")
        }
    }

    // MARK: Pure helpers (tested)

    /// The first mount point hdiutil's `-plist` attach output reports.
    static func mountPoint(fromAttachPlist data: Data) -> String? {
        guard let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let entities = plist["system-entities"] as? [[String: Any]]
        else { return nil }
        return entities.compactMap { $0["mount-point"] as? String }.first
    }

    /// Rejects a staged bundle that is not this app or not the promised
    /// release — a wrong or tampered asset must never replace the install.
    static func validationProblem(info: [String: Any], expectedBundleID: String, expectedVersion: String) -> String? {
        let identifier = info["CFBundleIdentifier"] as? String ?? ""
        guard identifier == expectedBundleID else {
            return "it is \(identifier.isEmpty ? "an unidentified bundle" : identifier), not \(expectedBundleID)"
        }
        let version = GitHubUpdateChecker.normalize(info["CFBundleShortVersionString"] as? String ?? "")
        guard version == GitHubUpdateChecker.normalize(expectedVersion) else {
            return "it is version \(version.isEmpty ? "unknown" : version), not \(expectedVersion)"
        }
        return nil
    }

    /// Why the bundle at `url` cannot be swapped in place, or nil when it can.
    static func installBlocker(forBundleAt url: URL, fileManager: FileManager = .default) -> String? {
        guard url.pathExtension == "app" else {
            return "the app is not running from an installed .app bundle"
        }
        if url.path.contains("/AppTranslocation/") {
            return "macOS is running a translocated copy; drag WinterVoice to Applications first"
        }
        guard fileManager.isWritableFile(atPath: url.deletingLastPathComponent().path),
              fileManager.isWritableFile(atPath: url.path)
        else {
            return "no permission to replace \(url.path)"
        }
        return nil
    }

    /// Waits for the given pid to exit, then reopens the app at `appPath`.
    /// Single-quoted so paths with spaces or quotes survive the shell.
    static func relaunchShellScript(pid: Int32, appPath: String) -> String {
        let quoted = appPath.replacingOccurrences(of: "'", with: "'\\''")
        return "while /bin/kill -0 \(pid) 2>/dev/null; do /bin/sleep 0.1; done; /usr/bin/open '\(quoted)'"
    }

    // MARK: Subprocess plumbing

    @discardableResult
    private static func run(_ tool: String, _ arguments: [String]) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: tool)
            process.arguments = arguments
            let stdout = Pipe()
            process.standardOutput = stdout
            process.standardError = Pipe()
            process.terminationHandler = { finished in
                let output = stdout.fileHandleForReading.readDataToEndOfFile()
                if finished.terminationStatus == 0 {
                    continuation.resume(returning: output)
                } else {
                    continuation.resume(throwing: UpdateInstallError.badImage(
                        "\(URL(fileURLWithPath: tool).lastPathComponent) exited with status \(finished.terminationStatus)"
                    ))
                }
            }
            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}
