import SwiftUI

struct HistoryView: View {
    @ObservedObject var store: HistoryStore
    @State private var searchText = ""

    private var filteredEntries: [HistoryEntry] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return store.entries }
        return store.entries.filter { $0.text.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        Group {
            if !store.isLoaded {
                ProgressView("Loading history…")
            } else if store.entries.isEmpty {
                ContentUnavailableView(
                    "No Dictation History",
                    systemImage: "clock.arrow.circlepath",
                    description: Text("Successfully inserted dictations will appear here.")
                )
            } else if filteredEntries.isEmpty {
                ContentUnavailableView.search(text: searchText)
            } else {
                List {
                    ForEach(filteredEntries) { entry in
                        HistoryEntryRow(entry: entry) {
                            store.delete(entry)
                        }
                    }
                }
            }
        }
        .navigationTitle("History")
        .searchable(text: $searchText, prompt: "Search dictations")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Clear All", role: .destructive) {
                    store.clear()
                }
                .disabled(store.entries.isEmpty)
            }
        }
    }
}

private struct HistoryEntryRow: View {
    let entry: HistoryEntry
    let delete: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "text.quote")
                .foregroundStyle(.secondary)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 6) {
                Text(entry.text)
                    .textSelection(.enabled)
                Text(entry.createdAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Button("Delete", systemImage: "trash", role: .destructive, action: delete)
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .help("Delete dictation")
        }
        .padding(.vertical, 5)
    }
}
