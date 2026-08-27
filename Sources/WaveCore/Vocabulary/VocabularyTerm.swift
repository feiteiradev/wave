import Foundation

/// A single custom-vocabulary entry: the canonical spelling plus the
/// mis-recognitions that should be rewritten to it (PRD §19).
public struct VocabularyTerm: Codable, Sendable, Hashable, Identifiable {
    public var id: UUID
    /// The spelling Wave should produce, e.g. `DearLift`.
    public var term: String
    /// Things the STT is likely to emit instead, e.g. `dear lift`, `deer lift`.
    public var aliases: [String]

    public init(id: UUID = UUID(), term: String, aliases: [String] = []) {
        self.id = id
        self.term = term
        self.aliases = aliases
    }
}
