import Foundation
import XCTest
@testable import WinterVoice

@MainActor
final class UpdateCheckerTests: XCTestCase {
    // MARK: Version comparison

    func testVersionComparison() {
        XCTAssertTrue(GitHubUpdateChecker.isVersion("0.4.0", newerThan: "0.3.1"))
        XCTAssertTrue(GitHubUpdateChecker.isVersion("1.0", newerThan: "0.9.9"))
        XCTAssertTrue(GitHubUpdateChecker.isVersion("0.3.10", newerThan: "0.3.9"))
        XCTAssertFalse(GitHubUpdateChecker.isVersion("0.3.1", newerThan: "0.3.1"))
        XCTAssertFalse(GitHubUpdateChecker.isVersion("0.3.0", newerThan: "0.3.1"))
        XCTAssertFalse(GitHubUpdateChecker.isVersion("0.3", newerThan: "0.3.0"))
    }

    func testTagNormalizationStripsLeadingV() {
        XCTAssertEqual(GitHubUpdateChecker.normalize("v0.4.0"), "0.4.0")
        XCTAssertEqual(GitHubUpdateChecker.normalize("0.4.0"), "0.4.0")
    }

    // MARK: Release parsing

    private func makeRelease(
        tag: String = "v0.4.0",
        body: String? = "## What's new\n\n- 🎯 **Faster models**\n- New importer\n\n## Install\n\n- Drag to Applications"
    ) -> GitHubUpdateChecker.Release {
        GitHubUpdateChecker.Release(
            tagName: tag,
            htmlURL: "https://github.com/winterzxzz/winter_voice/releases/tag/\(tag)",
            body: body,
            assets: [.init(
                name: "WinterVoice.dmg",
                browserDownloadURL: "https://github.com/winterzxzz/winter_voice/releases/download/\(tag)/WinterVoice.dmg"
            )]
        )
    }

    func testNewerReleaseBecomesAvailableUpdate() throws {
        let update = try XCTUnwrap(
            GitHubUpdateChecker.availableUpdate(from: makeRelease(), currentVersion: "0.3.1")
        )
        XCTAssertEqual(update.version, "0.4.0")
        XCTAssertEqual(update.highlights, ["🎯 **Faster models**", "New importer"])
        XCTAssertEqual(update.downloadURL?.lastPathComponent, "WinterVoice.dmg")
    }

    func testCurrentOrOlderReleaseYieldsNoUpdate() {
        XCTAssertNil(GitHubUpdateChecker.availableUpdate(from: makeRelease(tag: "v0.3.1"), currentVersion: "0.3.1"))
        XCTAssertNil(GitHubUpdateChecker.availableUpdate(from: makeRelease(tag: "v0.2.0"), currentVersion: "0.3.1"))
    }

    func testHighlightsExcludeInstallSection() {
        let highlights = GitHubUpdateChecker.highlights(
            fromReleaseNotes: "## What's new\n- One\n- Two\n\n## Install\n- Drag to Applications"
        )
        XCTAssertEqual(highlights, ["One", "Two"])
    }

    func testHighlightsFallBackToAllBulletsWithoutHeading() {
        let highlights = GitHubUpdateChecker.highlights(fromReleaseNotes: "- Solo bullet\n* Star bullet")
        XCTAssertEqual(highlights, ["Solo bullet", "Star bullet"])
    }

    // MARK: Controller

    private func makeDefaults() throws -> UserDefaults {
        let suite = "UpdateCheckerTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        return defaults
    }

    private func makeUpdate(version: String = "0.4.0") -> AvailableUpdate {
        AvailableUpdate(
            version: version,
            highlights: ["One"],
            downloadURL: URL(string: "https://example.com/WinterVoice.dmg"),
            releaseURL: URL(string: "https://example.com/release")!
        )
    }

    private func drainMainQueue() async {
        // Controller actions hop through one Task; two yields let the
        // MainActor run it to completion deterministically.
        await Task.yield()
        await Task.yield()
    }

    func testAutomaticCheckSurfacesUpdateOncePerDay() async throws {
        let defaults = try makeDefaults()
        let checker = UpdateCheckingStub(result: .success(makeUpdate()))
        var clock = Date(timeIntervalSince1970: 1_000_000)
        let controller = UpdateController(
            checker: checker, defaults: defaults, openURL: { _ in }, now: { clock }
        )

        controller.checkAutomatically()
        await drainMainQueue()
        XCTAssertEqual(controller.state, .available(makeUpdate()))
        XCTAssertEqual(checker.fetchCount, 1)

        // A fresh launch inside the throttle window stays quiet.
        let second = UpdateController(
            checker: checker, defaults: defaults, openURL: { _ in }, now: { clock }
        )
        second.checkAutomatically()
        await drainMainQueue()
        XCTAssertEqual(checker.fetchCount, 1)

        // A launch a day later checks again.
        clock = clock.addingTimeInterval(60 * 60 * 25)
        let third = UpdateController(
            checker: checker, defaults: defaults, openURL: { _ in }, now: { clock }
        )
        third.checkAutomatically()
        await drainMainQueue()
        XCTAssertEqual(checker.fetchCount, 2)
    }

    func testSkippedVersionStaysSilentOnAutomaticCheckUntilManualCheck() async throws {
        let defaults = try makeDefaults()
        let checker = UpdateCheckingStub(result: .success(makeUpdate()))
        let controller = UpdateController(
            checker: checker, defaults: defaults, openURL: { _ in }, now: { Date(timeIntervalSince1970: 0) }
        )

        controller.checkAutomatically()
        await drainMainQueue()
        controller.skip(makeUpdate())
        XCTAssertEqual(controller.state, .idle)

        // Next launch: same version, still skipped.
        let relaunched = UpdateController(
            checker: checker, defaults: defaults, openURL: { _ in },
            now: { Date(timeIntervalSince1970: 60 * 60 * 25) }
        )
        relaunched.checkAutomatically()
        await drainMainQueue()
        XCTAssertEqual(relaunched.state, .idle)

        // Manual check clears the skip and reports the release.
        relaunched.checkNow()
        await drainMainQueue()
        XCTAssertEqual(relaunched.state, .available(makeUpdate()))
    }

    func testManualCheckReportsUpToDateAndFailure() async throws {
        let defaults = try makeDefaults()
        let upToDate = UpdateController(
            checker: UpdateCheckingStub(result: .success(nil)),
            defaults: defaults, openURL: { _ in }, now: Date.init
        )
        upToDate.checkNow()
        XCTAssertEqual(upToDate.state, .checking)
        await drainMainQueue()
        XCTAssertEqual(upToDate.state, .upToDate)

        let failing = UpdateController(
            checker: UpdateCheckingStub(result: .failure(URLError(.notConnectedToInternet))),
            defaults: defaults, openURL: { _ in }, now: Date.init
        )
        failing.checkNow()
        await drainMainQueue()
        guard case .failed = failing.state else {
            return XCTFail("Expected a failed state, got \(failing.state)")
        }
    }

    func testDownloadPrefersDMGAssetAndFallsBackToReleasePage() {
        var opened: [URL] = []
        let controller = UpdateController(
            checker: UpdateCheckingStub(result: .success(nil)),
            defaults: .standard, openURL: { opened.append($0) }, now: Date.init
        )

        controller.download(makeUpdate())
        XCTAssertEqual(opened.last?.lastPathComponent, "WinterVoice.dmg")

        let withoutAsset = AvailableUpdate(
            version: "0.4.0", highlights: [], downloadURL: nil,
            releaseURL: URL(string: "https://example.com/release")!
        )
        controller.download(withoutAsset)
        XCTAssertEqual(opened.last?.absoluteString, "https://example.com/release")
    }
}

@MainActor
private final class UpdateCheckingStub: UpdateChecking {
    private let result: Result<AvailableUpdate?, Error>
    private(set) var fetchCount = 0

    init(result: Result<AvailableUpdate?, Error>) {
        self.result = result
    }

    func fetchAvailableUpdate() async throws -> AvailableUpdate? {
        fetchCount += 1
        return try result.get()
    }
}
