import XCTest
@testable import WinterVoice

final class AppShellSemanticsTests: XCTestCase {
    func testSidebarDestinationsAreAvailable() {
        let destinations: [AppShellDestination] = [
            .overview, .history, .dictionary, .hotkey, .settings
        ]
        XCTAssertTrue(destinations.allSatisfy { $0.availability == .available })
    }

    func testEveryDestinationHasExactlyOneAvailability() {
        XCTAssertEqual(AppShellDestination.allCases.count, 5)
        XCTAssertTrue(AppShellDestination.allCases.allSatisfy { $0.availability == .available })
    }
}
