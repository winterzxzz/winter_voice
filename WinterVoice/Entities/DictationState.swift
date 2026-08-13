import Foundation

enum DictationState: Equatable, Sendable {
    case idle
    case preparing
    case recording
    case processing
    case inserting
    case failed(DictationFailure)

    var isVisible: Bool { self != .idle }
}

struct DictationFailure: Error, Equatable, Sendable {
    let message: String
    let recovery: String
}

struct TextInsertionTarget: Hashable, Sendable {
    let id: UUID
}

struct InsertionOutcome: Equatable, Sendable {
    let landedInSecureField: Bool
}

enum DictationTransitionError: Error, Equatable {
    case invalid(from: DictationState, to: DictationState)
}

struct DictationStateMachine {
    private(set) var state: DictationState = .idle

    mutating func transition(to next: DictationState) throws {
        guard Self.canTransition(from: state, to: next) else {
            throw DictationTransitionError.invalid(from: state, to: next)
        }
        state = next
    }

    static func canTransition(from: DictationState, to: DictationState) -> Bool {
        switch (from, to) {
        case (.idle, .preparing),
             (.preparing, .recording),
             (.recording, .processing),
             (.processing, .inserting),
             (.inserting, .idle),
             (.failed, .idle):
            return true
        case (.idle, .failed),
             (.preparing, .failed),
             (.recording, .failed),
             (.processing, .failed),
             (.inserting, .failed):
            return true
        default:
            return false
        }
    }
}
