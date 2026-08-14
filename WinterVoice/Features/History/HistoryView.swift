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
        WVPage(
            icon: "clock.arrow.circlepath",
            title: "History",
            subtitle: "Everything you've dictated on this device."
        ) {
            if !store.entries.isEmpty {
                HStack(spacing: 8) {
                    WVSearchField(prompt: "Search dictations", text: $searchText)
                    Button("Clear All", role: .destructive) { store.clear() }
                        .buttonStyle(.wvSecondary(role: .destructive))
                }
            }
            content
        }
    }

    @ViewBuilder
    private var content: some View {
        if !store.isLoaded {
            WVCard {
                HStack {
                    Spacer()
                    ProgressView("Loading history…").foregroundStyle(Theme.textSecondary)
                    Spacer()
                }
                .padding(.vertical, 24)
            }
        } else if store.entries.isEmpty {
            WVDashedEmptyState(
                icon: "mic",
                title: "No transcriptions yet",
                message: "Hold your shortcut in any app to dictate — it'll show up here."
            )
        } else if filteredEntries.isEmpty {
            WVDashedEmptyState(
                icon: "magnifyingglass",
                title: "No matches",
                message: "No dictations contain “\(searchText)”."
            )
        } else {
            VStack(spacing: 10) {
                ForEach(filteredEntries) { entry in
                    HistoryEntryRow(entry: entry) { store.delete(entry) }
                }
            }
        }
    }
}

private struct HistoryEntryRow: View {
    let entry: HistoryEntry
    let delete: () -> Void
    @State private var isHovering = false

    var body: some View {
        WVCard {
            HStack(alignment: .top, spacing: Theme.Space.sm) {
                Image(systemName: "text.quote")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textTertiary)
                    .padding(.top, 2)
                VStack(alignment: .leading, spacing: 6) {
                    Text(entry.text)
                        .font(.wvBody)
                        .foregroundStyle(Theme.textPrimary)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(entry.createdAt.formatted(date: .abbreviated, time: .shortened))
                        .font(.wvCaption)
                        .foregroundStyle(Theme.textTertiary)
                }
                Spacer(minLength: 0)
                Button(action: delete) {
                    Image(systemName: "trash")
                        .font(.system(size: 13))
                        .foregroundStyle(isHovering ? Theme.danger : Theme.textTertiary)
                }
                .buttonStyle(.plain)
                .help("Delete dictation")
            }
        }
        .onHover { isHovering = $0 }
    }
}
