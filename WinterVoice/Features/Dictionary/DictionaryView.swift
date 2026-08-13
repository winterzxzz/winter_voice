import SwiftUI

struct DictionaryView: View {
    @ObservedObject var store: DictionaryStore
    @State private var source = ""
    @State private var replacement = ""
    @State private var errorMessage: String?
    @State private var editingEntry: DictionaryEntry?

    var body: some View {
        WVPage(
            icon: "character.book.closed",
            title: "Dictionary",
            subtitle: "Fix words and phrases transcription often gets wrong."
        ) {
            addCard
            replacementsCard
            WVCard {
                Text("Enabled replacements are applied to the transcription before it is inserted and saved in History. Longer phrases are matched before shorter ones.")
                    .font(.wvCaption)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .sheet(item: $editingEntry) { entry in
            DictionaryEditView(store: store, entry: entry)
        }
    }

    private var addCard: some View {
        WVCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("Add Replacement")
                    .font(.wvHeadline)
                    .foregroundStyle(Theme.textPrimary)
                HStack(alignment: .bottom, spacing: 10) {
                    WVField(label: "Word or phrase") {
                        TextField("", text: $source).textFieldStyle(.wv)
                    }
                    WVField(label: "Replace with") {
                        TextField("", text: $replacement).textFieldStyle(.wv)
                    }
                    Button("Add") { addEntry() }
                        .buttonStyle(.wvPrimary)
                }
                if let errorMessage {
                    Text(errorMessage).font(.wvCaption).foregroundStyle(Theme.danger)
                }
            }
        }
    }

    @ViewBuilder
    private var replacementsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("CUSTOM REPLACEMENTS")
                .font(.system(size: 11, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(Theme.textTertiary)
            if !store.isLoaded {
                WVCard { HStack { Spacer(); ProgressView("Loading dictionary…"); Spacer() }.padding(.vertical, 16) }
            } else if store.entries.isEmpty {
                WVCard {
                    Text("No replacements yet. Add names, product terms, or phrases that transcription often gets wrong.")
                        .font(.wvBody)
                        .foregroundStyle(Theme.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 8)
                }
            } else {
                WVCard(padding: 6) {
                    VStack(spacing: 0) {
                        ForEach(Array(store.entries.enumerated()), id: \.element.id) { index, entry in
                            if index > 0 { WVDivider().padding(.horizontal, 10) }
                            entryRow(entry).padding(10)
                        }
                    }
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
            .toggleStyle(.switch)
            .tint(Theme.accent)
            .labelsHidden()

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.source)
                    .font(.wvRowTitle)
                    .foregroundStyle(entry.isEnabled ? Theme.textPrimary : Theme.textSecondary)
                Text("→ \(entry.replacement)")
                    .font(.wvCaption)
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer(minLength: Theme.Space.sm)
            Button("Edit") { editingEntry = entry }
                .buttonStyle(.wvSecondary)
            Button(action: { store.delete(entry) }) {
                Image(systemName: "trash").font(.system(size: 13))
            }
            .buttonStyle(.wvGhost(role: .destructive))
        }
    }

    private func addEntry() {
        do {
            try store.add(source: source, replacement: replacement)
            source = ""
            replacement = ""
            errorMessage = nil
        } catch let error as DictionaryStoreError {
            errorMessage = error.message
        } catch {
            errorMessage = "Could not save this replacement."
        }
    }
}

private struct DictionaryEditView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: DictionaryStore
    let entry: DictionaryEntry
    @State private var source: String
    @State private var replacement: String
    @State private var errorMessage: String?

    init(store: DictionaryStore, entry: DictionaryEntry) {
        self.store = store
        self.entry = entry
        _source = State(initialValue: entry.source)
        _replacement = State(initialValue: entry.replacement)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Edit Replacement")
                .font(.wvTitle)
                .foregroundStyle(Theme.textPrimary)
            WVField(label: "Word or phrase") {
                TextField("", text: $source).textFieldStyle(.wv)
            }
            WVField(label: "Replace with") {
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
            try store.update(entry, source: source, replacement: replacement)
            dismiss()
        } catch let error as DictionaryStoreError {
            errorMessage = error.message
        } catch {
            errorMessage = "Could not save this replacement."
        }
    }
}
