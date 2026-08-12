import Combine

@MainActor
final class HotkeyHealthRelay: ObservableObject {
    @Published private(set) var health: HotkeyHealth = .permissionRequired

    func publish(_ health: HotkeyHealth) {
        self.health = health
    }
}
