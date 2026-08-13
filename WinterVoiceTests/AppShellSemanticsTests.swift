import XCTest
@testable import WinterVoice

final class AppShellSemanticsTests: XCTestCase {
    func testOperationalDestinationsAreAvailable() {
        let destinations: [AppShellDestination] = [
            .overview, .permissions, .transcription, .hotkey, .privacy, .models, .remoteProviders
        ]
        XCTAssertTrue(destinations.allSatisfy { $0.availability == .available })
    }

    func testDataDestinationsAreAvailable() {
        let destinations: [AppShellDestination] = [
            .history, .dictionary
        ]
        XCTAssertTrue(destinations.allSatisfy { $0.availability == .available })
    }

    func testEveryDestinationHasExactlyOneAvailability() {
        XCTAssertEqual(AppShellDestination.allCases.count, 9)
        XCTAssertTrue(AppShellDestination.allCases.allSatisfy { $0.availability == .available })
    }
}
