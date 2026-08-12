import Combine

@MainActor
final class DictationStateRelay: ObservableObject {
    @Published private(set) var state: DictationState = .idle

    func publish(_ state: DictationState) {
        self.state = state
    }
}
