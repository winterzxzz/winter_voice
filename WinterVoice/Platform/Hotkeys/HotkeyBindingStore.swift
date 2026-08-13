import Combine
import Foundation

@MainActor
final class HotkeyBindingStore: ObservableObject {
    @Published var selection: HotkeyBinding {
        didSet { defaults.set(try? JSONEncoder().encode(selection), forKey: Self.key) }
    }

    private static let key = "hotkey.binding"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        // Earlier MVP builds stored enum strings such as "rightOption".
        // Treat that legacy format as unset so the new default is Fn/Globe.
        if defaults.string(forKey: Self.key) != nil {
            defaults.removeObject(forKey: Self.key)
        }
        selection = defaults.data(forKey: Self.key)
            .flatMap { try? JSONDecoder().decode(HotkeyBinding.self, from: $0) }
            ?? .function
    }
}
