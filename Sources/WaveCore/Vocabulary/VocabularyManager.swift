import Foundation

/// Applies the global custom vocabulary to a transcription (PRD §19).
///
/// Vocabulary lives in the recognition layer, so it runs for both Raw and
/// Clean. Matching is case-insensitive and whole-word only — the MVP
/// deliberately does not do fuzzy matching (PRD §19.1).
public struct VocabularyManager: Sendable {
    public private(set) var terms: [VocabularyTerm]

    public init(terms: [VocabularyTerm] = []) {
        self.terms = terms
    }

    /// Hotword hints for STT engines that support biasing (PRD §19.1).
    public var hotwords: [String] {
        terms.map(\.term).filter { !$0.isEmpty }
    }

    public func normalize(_ text: String) -> String {
        guard !text.isEmpty else { return text }
        var result = text
        for replacement in replacements {
            result = replacement.apply(to: result)
        }
        return result
    }

    /// Longest aliases first, so `dear lift pro` is not half-eaten by `dear lift`.
    private var replacements: [AliasReplacement] {
        terms
            .flatMap { term in
                term.aliases
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty && $0.caseInsensitiveCompare(term.term) != .orderedSame }
                    .map { AliasReplacement(alias: $0, canonical: term.term) }
            }
            .sorted { $0.alias.count > $1.alias.count }
    }
}

private struct AliasReplacement {
    let alias: String
    let canonical: String

    func apply(to text: String) -> String {
        // Collapse whitespace inside the alias so "dear   lift" still matches.
        let escaped = NSRegularExpression.escapedPattern(for: alias)
            .replacingOccurrences(of: "\\ ", with: "\\s+")
            .replacingOccurrences(of: " ", with: "\\s+")
        guard let regex = try? NSRegularExpression(
            pattern: "\\b\(escaped)\\b",
            options: [.caseInsensitive]
        ) else { return text }
        let template = NSRegularExpression.escapedTemplate(for: canonical)
        return regex.stringByReplacingMatches(
            in: text,
            range: NSRange(text.startIndex..., in: text),
            withTemplate: template
        )
    }
}
