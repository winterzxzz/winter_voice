import Foundation

struct DictionaryEntry: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    let source: String
    let replacement: String
    let isEnabled: Bool

    init(
        id: UUID = UUID(),
        source: String,
        replacement: String,
        isEnabled: Bool = true
    ) {
        self.id = id
        self.source = source
        self.replacement = replacement
        self.isEnabled = isEnabled
    }
}
