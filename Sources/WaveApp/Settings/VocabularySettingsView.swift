import SwiftUI
import WaveCore

/// The one global custom vocabulary, shared by Raw and Clean (PRD §19).
///
/// Manually managed: Wave keeps no transcription history, so it has nothing to
/// learn suggestions from (PRD §19.3).
struct VocabularySettingsView: View {
    @EnvironmentObject private var model: AppModel
    @State private var selection: VocabularyTerm.ID?
    /// The alias editor's raw text.
    ///
    /// Held separately rather than derived from the model: round-tripping
    /// through `[String]` strips the trailing newline the moment Return is
    /// pressed, which makes it impossible to start a second alias line.
    @State private var aliasDraft: String = ""

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
                    TextEditor(text: $aliasDraft)
                        .font(.body.monospaced())
                        .frame(minHeight: 120)
                        .onChange(of: aliasDraft) { _, newValue in
                            model.preferences.vocabulary[index].aliases = Self.aliases(from: newValue)
                        }
                    Text("One per line. Matching ignores capitalization and only replaces whole words.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            .onChange(of: selection) { _, _ in loadDraft() }
            .onAppear(perform: loadDraft)
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
                aliasDraft = ""
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

    private func loadDraft() {
        guard let index = selectedIndex else { return }
        aliasDraft = model.preferences.vocabulary[index].aliases.joined(separator: "\n")
    }

    /// Blank lines are dropped on the way into the model, but stay visible in
    /// the editor while the user is typing.
    static func aliases(from text: String) -> [String] {
        text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
}
