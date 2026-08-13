import SwiftUI

struct DictionaryView: View {
    @ObservedObject var store: DictionaryStore
    @State private var source = ""
    @State private var replacement = ""
    @State private var errorMessage: String?
    @State private var editingEntry: DictionaryEntry?

    var body: some View {
        Form {
            Section("Add Replacement") {
                TextField("Word or phrase", text: $source)
                TextField("Replace with", text: $replacement)
                HStack {
                    Button("Add Entry") { addEntry() }
                        .buttonStyle(.borderedProminent)
                    if let errorMessage {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                }
            }

            Section("Custom Replacements") {
                if !store.isLoaded {
                    ProgressView("Loading dictionary…")
                } else if store.entries.isEmpty {
                    Text("No replacements yet. Add names, product terms, or phrases that transcription often gets wrong.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(store.entries) { entry in
                        HStack {
                            Toggle(isOn: Binding(
                                get: { entry.isEnabled },
                                set: { store.setEnabled($0, for: entry) }
                            )) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(entry.source)
                                    Text("→ (entry.replacement)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Button("Edit") { editingEntry = entry }
                            Button("Delete", systemImage: "trash", role: .destructive) {
                                store.delete(entry)
                            }
                            .labelStyle(.iconOnly)
                            .buttonStyle(.borderless)
                        }
                    }
                }
            }

            Section("How It Works") {
                Text("Enabled replacements are applied to the transcription before it is inserted and saved in History. Longer phrases are matched before shorter ones.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Dictionary")
        .sheet(item: $editingEntry) { entry in
            DictionaryEditView(store: store, entry: entry)
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
        VStack(alignment: .leading, spacing: 18) {
            Text("Edit Replacement")
                .font(.title2.bold())
            TextField("Word or phrase", text: $source)
            TextField("Replace with", text: $replacement)
            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Save") { save() }
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(width: 420)
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
