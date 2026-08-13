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
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.lg) {
                WVSectionHeader(
                    icon: "clock.arrow.circlepath",
                    title: "History",
                    subtitle: "Successfully inserted dictations, stored on this Mac."
                ) {
                    Button("Clear All", role: .destructive) { store.clear() }
                        .buttonStyle(.wvSecondary(role: .destructive))
                        .disabled(store.entries.isEmpty)
                }

                if !store.entries.isEmpty {
                    searchField
                }

                content
            }
            .frame(maxWidth: 760, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 40)
            .padding(.top, 40)
            .padding(.bottom, 48)
        }
        .scrollContentBackground(.hidden)
        .background(Theme.canvas)
    }

    @ViewBuilder
    private var content: some View {
        if !store.isLoaded {
            loadingOrEmpty {
                ProgressView("Loading history…").foregroundStyle(Theme.textSecondary)
            }
        } else if store.entries.isEmpty {
            emptyState(
                icon: "clock.arrow.circlepath",
                title: "No dictation history",
                message: "Successfully inserted dictations will appear here."
            )
        } else if filteredEntries.isEmpty {
            emptyState(
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

    private var searchField: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
        return HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.textTertiary)
            TextField("", text: $searchText, prompt: Text("Search dictations").foregroundColor(Theme.textTertiary))
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .foregroundStyle(Theme.textPrimary)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 8)
        .background(Theme.inset, in: shape)
        .overlay(shape.strokeBorder(Theme.border, lineWidth: 1))
    }

    private func loadingOrEmpty<V: View>(@ViewBuilder _ view: () -> V) -> some View {
        WVCard { HStack { Spacer(); view(); Spacer() }.padding(.vertical, 24) }
    }

    private func emptyState(icon: String, title: String, message: String) -> some View {
        WVCard {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 30, weight: .light))
                    .foregroundStyle(Theme.textTertiary)
                Text(title).font(.wvHeadline).foregroundStyle(Theme.textPrimary)
                Text(message).font(.wvBody).foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 32)
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
