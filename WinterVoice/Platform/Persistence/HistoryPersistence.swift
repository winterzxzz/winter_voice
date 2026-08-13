import Foundation

protocol HistoryPersisting: Sendable {
    func load() async -> [HistoryEntry]
    func save(_ entries: [HistoryEntry]) async throws
}

actor JSONHistoryPersistence: HistoryPersisting {
    private let root: URL
    private let fileManager = FileManager.default

    init(root: URL) {
        self.root = root
    }

    func load() async -> [HistoryEntry] {
        let url = root.appendingPathComponent("history.json")
        guard let data = try? Data(contentsOf: url),
              let entries = try? JSONDecoder().decode([HistoryEntry].self, from: data) else {
            return []
        }
        return entries
    }

    func save(_ entries: [HistoryEntry]) async throws {
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(entries)
        try data.write(to: root.appendingPathComponent("history.json"), options: .atomic)
    }
}

@MainActor
final class HistoryStore: ObservableObject, HistoryRecording {
    @Published private(set) var entries: [HistoryEntry] = []
    @Published private(set) var isLoaded = false

    private let persistence: any HistoryPersisting
    private let maxEntries: Int
    private var saveTask: Task<Void, Never>?
    private var hadLocalMutationBeforeLoad = false

    init(root: URL? = nil, persistence: (any HistoryPersisting)? = nil, maxEntries: Int = 500) {
        let applicationSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let resolvedRoot = root ?? applicationSupport.appendingPathComponent("WinterVoice", isDirectory: true)
        self.persistence = persistence ?? JSONHistoryPersistence(root: resolvedRoot)
        self.maxEntries = max(1, maxEntries)
        Task { [weak self] in await self?.loadPersistedEntries() }
    }

    func record(text: String) {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return }
        entries.insert(HistoryEntry(text: normalized), at: 0)
        entries = Array(entries.prefix(maxEntries))
        hadLocalMutationBeforeLoad = !isLoaded
        schedulePersist()
    }

    func delete(_ entry: HistoryEntry) {
        entries.removeAll { $0.id == entry.id }
        hadLocalMutationBeforeLoad = !isLoaded
        schedulePersist()
    }

    func clear() {
        guard !entries.isEmpty else { return }
        entries.removeAll()
        hadLocalMutationBeforeLoad = !isLoaded
        schedulePersist()
    }

    private func loadPersistedEntries() async {
        let persisted = await persistence.load()
        guard !isLoaded else { return }

        if hadLocalMutationBeforeLoad {
            let localIDs = Set(entries.map(\.id))
            entries = (entries + persisted.filter { !localIDs.contains($0.id) })
                .sorted { $0.createdAt > $1.createdAt }
        } else {
            entries = persisted.sorted { $0.createdAt > $1.createdAt }
        }
        entries = Array(entries.prefix(maxEntries))
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
