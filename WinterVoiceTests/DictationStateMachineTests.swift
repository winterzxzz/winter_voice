import XCTest
@testable import WinterVoice

final class DictationStateMachineTests: XCTestCase {
    func testHappyPath() throws {
        var machine = DictationStateMachine()
        for state in [DictationState.preparing, .recording, .processing, .inserting, .idle] {
            try machine.transition(to: state)
        }
        XCTAssertEqual(machine.state, .idle)
    }

    func testFailureCanRecoverToIdle() throws {
        var machine = DictationStateMachine()
        try machine.transition(to: .preparing)
        try machine.transition(to: .failed(.init(message: "No", recovery: "Retry")))
        try machine.transition(to: .idle)
        XCTAssertEqual(machine.state, .idle)
    }

    func testDuplicatePressTransitionIsRejected() throws {
        var machine = DictationStateMachine()
        try machine.transition(to: .preparing)
        XCTAssertThrowsError(try machine.transition(to: .preparing))
    }
}
