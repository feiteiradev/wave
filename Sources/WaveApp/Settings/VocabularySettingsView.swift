import SwiftUI
import WaveCore

/// The one global custom vocabulary, shared by Raw and Clean (PRD §19).
///
/// Manually managed: Wave keeps no transcription history, so it has nothing to
/// learn suggestions from (PRD §19.3).
struct VocabularySettingsView: View {
    @EnvironmentObject private var model: AppModel
    @State private var selection: VocabularyTerm.ID?

    var body: some View {
        VStack(spacing: 0) {
            HSplitView {
                termList
                termEditor
            }
            Divider()
            footer
        }
    }

    private var termList: some View {
        List(selection: $selection) {
            ForEach(model.preferences.vocabulary) { term in
                VStack(alignment: .leading, spacing: 2) {
                    Text(term.term.isEmpty ? "New term" : term.term)
                    if !term.aliases.isEmpty {
                        Text(term.aliases.joined(separator: ", "))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                .tag(term.id)
            }
        }
        .frame(minWidth: 170)
    }

    @ViewBuilder
    private var termEditor: some View {
        if let index = selectedIndex {
            Form {
                Section("Term") {
                    TextField("DearLift", text: $model.preferences.vocabulary[index].term)
                }
                Section("Also heard as") {
                    TextEditor(text: aliasesBinding(for: index))
                        .font(.body.monospaced())
                        .frame(minHeight: 120)
                    Text("One per line. Matching ignores capitalization and only replaces whole words.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
        } else {
            VStack(spacing: 6) {
                Text("No term selected").foregroundStyle(.secondary)
                Text("Add the names Wave gets wrong, with the spellings it produces instead.")
                    .font(.caption)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 24)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var footer: some View {
        HStack {
            Button {
                let term = VocabularyTerm(term: "", aliases: [])
                model.preferences.vocabulary.append(term)
                selection = term.id
            } label: {
                Image(systemName: "plus")
            }

            Button {
                guard let index = selectedIndex else { return }
                model.preferences.vocabulary.remove(at: index)
                selection = nil
            } label: {
                Image(systemName: "minus")
            }
            .disabled(selectedIndex == nil)

            Spacer()
        }
        .buttonStyle(.borderless)
        .padding(8)
    }

    private var selectedIndex: Int? {
        guard let selection else { return nil }
        return model.preferences.vocabulary.firstIndex { $0.id == selection }
    }

    private func aliasesBinding(for index: Int) -> Binding<String> {
        Binding(
            get: { model.preferences.vocabulary[index].aliases.joined(separator: "\n") },
            set: { newValue in
                model.preferences.vocabulary[index].aliases = newValue
                    .components(separatedBy: .newlines)
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }
            }
        )
    }
}
