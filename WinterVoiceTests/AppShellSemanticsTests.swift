import XCTest
@testable import WinterVoice

final class AppShellSemanticsTests: XCTestCase {
    func testOperationalDestinationsAreAvailable() {
        let destinations: [AppShellDestination] = [
            .overview, .permissions, .transcription, .hotkey, .privacy
        ]
        XCTAssertTrue(destinations.allSatisfy { $0.availability == .available })
    }

    func testDataDestinationsAreAvailable() {
        let destinations: [AppShellDestination] = [
            .history, .dictionary, .statistics
        ]
        XCTAssertTrue(destinations.allSatisfy { $0.availability == .available })
    }

    func testEveryDestinationHasExactlyOneAvailability() {
        XCTAssertEqual(AppShellDestination.allCases.count, 8)
        XCTAssertTrue(AppShellDestination.allCases.allSatisfy { $0.availability == .available })
    }
}
