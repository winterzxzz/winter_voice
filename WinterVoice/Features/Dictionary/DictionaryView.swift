import SwiftUI

struct DictionaryView: View {
    @ObservedObject var store: DictionaryStore
    @State private var searchText = ""
    @State private var sheet: TermSheetMode?

    private var filteredEntries: [DictionaryEntry] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return store.entries }
        return store.entries.filter {
            $0.source.localizedCaseInsensitiveContains(query)
                || $0.replacement.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        WVPage(
            icon: "character.book.closed",
            title: "Dictionary",
            subtitle: "Fix words WinterVoice gets wrong."
        ) {
            savedTermsCard
        } trailing: {
            Toggle(isOn: $store.isApplyEnabled) {
                Text("Apply to transcripts")
                    .font(.wvCaption)
                    .foregroundStyle(Theme.textSecondary)
            }
            .toggleStyle(.wv)
            .help("When off, saved terms are kept but not applied to new dictations.")
        }
        .sheet(item: $sheet) { mode in
            DictionaryTermSheet(store: store, mode: mode)
        }
    }

    private var savedTermsCard: some View {
        WVCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 8) {
                    Text("Saved Terms (\(store.entries.count))")
                        .font(.wvHeadline)
                        .foregroundStyle(Theme.textPrimary)
                    Spacer(minLength: Theme.Space.md)
                    WVSearchField(prompt: "Search terms", text: $searchText, width: 190)
                    WVIconButton(
                        systemImage: "arrow.triangle.2.circlepath",
                        help: "Reload saved terms from disk"
                    ) {
                        store.reload()
                    }
                    Button {
                        sheet = .add
                    } label: {
                        Label("Add term", systemImage: "plus")
                    }
                    .buttonStyle(.wvPrimary)
                }

                termsContent
            }
        }
    }

    @ViewBuilder
    private var termsContent: some View {
        if !store.isLoaded {
            HStack {
                Spacer()
                ProgressView("Loading dictionary…").foregroundStyle(Theme.textSecondary)
                Spacer()
            }
            .padding(.vertical, 24)
        } else if store.entries.isEmpty {
            WVDashedEmptyState(
                icon: "character.book.closed",
                title: "No terms saved yet",
                message: "Click “Add term” to fix your first misheard word."
            )
        } else if filteredEntries.isEmpty {
            WVDashedEmptyState(
                icon: "magnifyingglass",
                title: "No matches",
                message: "No saved terms contain “\(searchText)”."
            )
        } else {
            VStack(spacing: 0) {
                ForEach(Array(filteredEntries.enumerated()), id: \.element.id) { index, entry in
                    if index > 0 { WVDivider() }
                    entryRow(entry).padding(.vertical, 10)
                }
            }
        }
    }

    private func entryRow(_ entry: DictionaryEntry) -> some View {
        HStack(spacing: Theme.Space.sm) {
            Toggle("", isOn: Binding(
                get: { entry.isEnabled },
                set: { store.setEnabled($0, for: entry) }
            ))
            .toggleStyle(.wv)
            .labelsHidden()
            .help(entry.isEnabled ? "Term is applied to transcripts" : "Term is paused")

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.source)
                    .font(.wvRowTitle)
                    .foregroundStyle(entry.isEnabled ? Theme.textPrimary : Theme.textSecondary)
                Text("→ \(entry.replacement)")
                    .font(.wvCaption)
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer(minLength: Theme.Space.sm)
            Button("Edit") { sheet = .edit(entry) }
                .buttonStyle(.wvSecondary)
            Button(action: { store.delete(entry) }) {
                Image(systemName: "trash").font(.system(size: 13))
            }
            .buttonStyle(.wvGhost(role: .destructive))
        }
    }
}

// MARK: - Add / edit sheet

enum TermSheetMode: Identifiable {
    case add
    case edit(DictionaryEntry)

    var id: String {
        switch self {
        case .add: "add"
        case .edit(let entry): entry.id.uuidString
        }
    }
}

private struct DictionaryTermSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: DictionaryStore
    let mode: TermSheetMode
    @State private var source: String
    @State private var replacement: String
    @State private var errorMessage: String?

    init(store: DictionaryStore, mode: TermSheetMode) {
        self.store = store
        self.mode = mode
        switch mode {
        case .add:
            _source = State(initialValue: "")
            _replacement = State(initialValue: "")
        case .edit(let entry):
            _source = State(initialValue: entry.source)
            _replacement = State(initialValue: entry.replacement)
        }
    }

    private var isEditing: Bool {
        if case .edit = mode { return true }
        return false
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(isEditing ? "Edit Term" : "Add Term")
                .font(.wvTitle)
                .foregroundStyle(Theme.textPrimary)
            WVField(label: "Word or phrase WinterVoice hears") {
                TextField("", text: $source).textFieldStyle(.wv)
            }
            WVField(label: "What it should type instead") {
                TextField("", text: $replacement).textFieldStyle(.wv)
            }
            if let errorMessage {
                Text(errorMessage).font(.wvCaption).foregroundStyle(Theme.danger)
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.buttonStyle(.wvSecondary)
                Button("Save") { save() }.buttonStyle(.wvPrimary)
            }
            .padding(.top, 4)
        }
        .padding(24)
        .frame(width: 440)
        .background(Theme.canvas)
        .tint(Theme.accent)
        .preferredColorScheme(.dark)
    }

    private func save() {
        do {
            switch mode {
            case .add:
                try store.add(source: source, replacement: replacement)
            case .edit(let entry):
                try store.update(entry, source: source, replacement: replacement)
            }
            dismiss()
        } catch let error as DictionaryStoreError {
            errorMessage = error.message
        } catch {
            errorMessage = "Could not save this term."
        }
    }
}
