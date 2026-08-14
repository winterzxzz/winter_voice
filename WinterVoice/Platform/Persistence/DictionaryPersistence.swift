import Foundation

protocol DictionaryPersisting: Sendable {
    func load() async -> [DictionaryEntry]
    func save(_ entries: [DictionaryEntry]) async throws
}

actor JSONDictionaryPersistence: DictionaryPersisting {
    private let root: URL
    private let fileManager = FileManager.default

    init(root: URL) {
        self.root = root
    }

    func load() async -> [DictionaryEntry] {
        let url = root.appendingPathComponent("dictionary.json")
        guard let data = try? Data(contentsOf: url),
              let entries = try? JSONDecoder().decode([DictionaryEntry].self, from: data) else {
            return []
        }
        return entries
    }

    func save(_ entries: [DictionaryEntry]) async throws {
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(entries)
        try data.write(to: root.appendingPathComponent("dictionary.json"), options: .atomic)
    }
}

enum DictionaryStoreError: Error, Equatable {
    case emptySource
    case duplicateSource

    var message: String {
        switch self {
        case .emptySource: "Enter a word or phrase to replace."
        case .duplicateSource: "That word or phrase already exists."
        }
    }
}

@MainActor
final class DictionaryStore: ObservableObject, TextProcessing {
    @Published private(set) var entries: [DictionaryEntry] = []
    @Published private(set) var isLoaded = false

    /// Master switch: when off, saved terms are kept but not applied to
    /// transcripts (the "Apply to transcripts" toggle).
    @Published var isApplyEnabled: Bool {
        didSet { defaults.set(isApplyEnabled, forKey: Self.applyEnabledKey) }
    }

    private static let applyEnabledKey = "dictionary.applyEnabled"
    private let defaults: UserDefaults
    private let persistence: any DictionaryPersisting
    private var saveTask: Task<Void, Never>?
    private var hadLocalMutationBeforeLoad = false

    init(
        root: URL? = nil,
        persistence: (any DictionaryPersisting)? = nil,
        defaults: UserDefaults = .standard
    ) {
        let applicationSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let resolvedRoot = root ?? applicationSupport.appendingPathComponent("WinterVoice", isDirectory: true)
        self.persistence = persistence ?? JSONDictionaryPersistence(root: resolvedRoot)
        self.defaults = defaults
        isApplyEnabled = defaults.object(forKey: Self.applyEnabledKey) as? Bool ?? true
        Task { [weak self] in await self?.loadPersistedEntries() }
    }

    /// Re-read the saved terms from disk, waiting out any in-flight save so a
    /// debounced write is never clobbered.
    func reload() {
        let persistence = persistence
        let pendingSave = saveTask
        Task { [weak self] in
            await pendingSave?.value
            let persisted = await persistence.load()
            guard let self else { return }
            self.entries = persisted
            self.isLoaded = true
        }
    }

    func add(source: String, replacement: String) throws {
        let source = try normalizedSource(source)
        guard !entries.contains(where: { $0.source == source }) else {
            throw DictionaryStoreError.duplicateSource
        }
        entries.append(DictionaryEntry(source: source, replacement: replacement))
        hadLocalMutationBeforeLoad = !isLoaded
        schedulePersist()
    }

    func update(_ entry: DictionaryEntry, source: String, replacement: String) throws {
        let source = try normalizedSource(source)
        guard !entries.contains(where: { $0.id != entry.id && $0.source == source }) else {
            throw DictionaryStoreError.duplicateSource
        }
        guard let index = entries.firstIndex(where: { $0.id == entry.id }) else { return }
        entries[index] = DictionaryEntry(
            id: entry.id,
            source: source,
            replacement: replacement,
            isEnabled: entry.isEnabled
        )
        hadLocalMutationBeforeLoad = !isLoaded
        schedulePersist()
    }

    func setEnabled(_ enabled: Bool, for entry: DictionaryEntry) {
        guard let index = entries.firstIndex(where: { $0.id == entry.id }) else { return }
        entries[index] = DictionaryEntry(
            id: entry.id,
            source: entry.source,
            replacement: entry.replacement,
            isEnabled: enabled
        )
        hadLocalMutationBeforeLoad = !isLoaded
        schedulePersist()
    }

    func delete(_ entry: DictionaryEntry) {
        entries.removeAll { $0.id == entry.id }
        hadLocalMutationBeforeLoad = !isLoaded
        schedulePersist()
    }

    func process(_ text: String) -> String {
        guard isApplyEnabled else { return text }

        struct Candidate {
            let range: NSRange
            let replacement: String
        }

        let original = text as NSString
        var candidates: [Candidate] = []

        for entry in entries where entry.isEnabled && !entry.source.isEmpty {
            var searchLocation = 0
            while searchLocation < original.length {
                let searchRange = NSRange(
                    location: searchLocation,
                    length: original.length - searchLocation
                )
                let match = original.range(of: entry.source, options: [], range: searchRange)
                guard match.location != NSNotFound else { break }
                candidates.append(Candidate(range: match, replacement: entry.replacement))
                searchLocation = match.location + max(match.length, 1)
            }
        }

        // Resolve overlaps against the original text. Longer entries win, so
        // replacements never cascade into text produced by another entry.
        let selected = candidates.sorted {
            if $0.range.length != $1.range.length { return $0.range.length > $1.range.length }
            return $0.range.location < $1.range.location
        }.reduce(into: [Candidate]()) { result, candidate in
            let overlaps = result.contains { existing in
                NSIntersectionRange(existing.range, candidate.range).length > 0
            }
            if !overlaps { result.append(candidate) }
        }

        let output = NSMutableString(string: original)
        for candidate in selected.sorted(by: { $0.range.location > $1.range.location }) {
            output.replaceCharacters(in: candidate.range, with: candidate.replacement)
        }
        return output as String
    }

    private func normalizedSource(_ source: String) throws -> String {
        let normalized = source.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { throw DictionaryStoreError.emptySource }
        return normalized
    }

    private func loadPersistedEntries() async {
        let persisted = await persistence.load()
        guard !isLoaded else { return }

        if hadLocalMutationBeforeLoad {
            let localIDs = Set(entries.map(\.id))
            entries += persisted.filter { !localIDs.contains($0.id) }
        } else {
            entries = persisted
        }
        isLoaded = true
        if hadLocalMutationBeforeLoad {
            schedulePersist()
        }
    }

    private func schedulePersist() {
        let snapshot = entries
        let persistence = persistence
        let previous = saveTask
        saveTask = Task {
            await previous?.value
            try? await persistence.save(snapshot)
        }
    }
}
