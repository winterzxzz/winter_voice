import XCTest
@testable import WinterVoice

final class AppShellSemanticsTests: XCTestCase {
    func testOperationalDestinationsAreAvailable() {
        let destinations: [AppShellDestination] = [
            .overview, .permissions, .transcription, .hotkey, .privacy, .models, .remoteProviders
        ]
        XCTAssertTrue(destinations.allSatisfy { $0.availability == .available })
    }

    func testRoadmapDestinationsArePlanned() {
        let destinations: [AppShellDestination] = [
            .history, .dictionary
        ]
        XCTAssertTrue(destinations.allSatisfy { $0.availability == .planned })
    }

    func testEveryDestinationHasExactlyOneAvailability() {
        XCTAssertEqual(AppShellDestination.allCases.count, 9)
        XCTAssertEqual(
            AppShellDestination.allCases.filter { $0.availability == .planned }.count,
            2
        )
    }
}
