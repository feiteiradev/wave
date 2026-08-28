import Foundation

/// Turns dictated punctuation words into symbols — "vírgula" → `,` (PRD §7.2).
///
/// Clean only. Raw's contract is "what I said", so it never runs there; it is
/// invoked from `CleanupRules`, which itself only runs in Clean mode.
///
/// One combined English + Portuguese table rather than a language-keyed one:
/// the speaker code-switches mid-sentence, and a table scoped to the selected
/// language would silently miss whichever half was not active.
///
/// The Portuguese commands are Apple's documented pt-PT dictation list, so a
/// user arriving from macOS Dictation already knows them. Note it is "ponto
/// final", never a bare "ponto" — which is what leaves "readme ponto md"
/// alone.
struct SpokenPunctuation: Sendable {
    /// Deliberately the low-risk set: terminators, separators and brackets, the
    /// same safe list other dictation tools converge on. "dash", "hyphen" and
    /// "quote" are left out on purpose — they are said literally far too often
    /// when dictating about code to be worth the false triggers.
    static let commands: [String: String] = [
        // Portuguese (Apple pt-PT dictation commands)
        "ponto final": ".",
        "ponto de interrogação": "?",
        "ponto de exclamação": "!",
        "ponto e vírgula": ";",
        "dois pontos": ":",
        "vírgula": ",",
        "reticências": "…",
        "abrir parêntese": "(",
        "fechar parêntese": ")",
        "nova linha": "\n",
        "novo parágrafo": "\n\n",
        // English
        "period": ".",
        "full stop": ".",
        "question mark": "?",
        "exclamation mark": "!",
        "exclamation point": "!",
        "semicolon": ";",
        "colon": ":",
        "comma": ",",
        "ellipsis": "…",
        "open parenthesis": "(",
        "close parenthesis": ")",
        "new line": "\n",
        "new paragraph": "\n\n",
    ]

    /// An article before the command means the speaker is talking *about* the
    /// mark, not asking for it: "a vírgula que falta", "the period goes here".
    /// The only cheap literal-escape technique in general use.
    ///
    /// ponytail: the Portuguese half of this list is inference, not a documented
    /// behaviour anywhere — widen it if real dictation shows misses.
    static let determiners = [
        "o", "a", "os", "as", "um", "uma", "este", "esta", "esse", "essa", "aquele", "aquela",
        "the", "an", "my", "this", "that",
    ]

    /// Longest phrase first, so "ponto e vírgula" is not half-eaten by
    /// "vírgula", and accent-folded variants are accepted because the STT does
    /// not always spell "vírgula" with its accent.
    private static let pattern: NSRegularExpression? = {
        let phrases = commands.keys
            .flatMap { [$0, $0.folding(options: .diacriticInsensitive, locale: Locale(identifier: "pt_PT"))] }
            .reduce(into: [String]()) { unique, phrase in
                if !unique.contains(phrase) { unique.append(phrase) }
            }
            .sorted { $0.count > $1.count }
            .map { NSRegularExpression.escapedPattern(for: $0).replacingOccurrences(of: " ", with: "\\s+") }
        let determinerAlternation = determiners
            .map { NSRegularExpression.escapedPattern(for: $0) }
            .joined(separator: "|")
        return try? NSRegularExpression(
            pattern: "(\\b(?:\(determinerAlternation))\\s+)?\\b(\(phrases.joined(separator: "|")))\\b",
            options: [.caseInsensitive]
        )
    }()

    /// Accent-folded lookup, so "virgula" and "vírgula" resolve alike.
    private static let symbolsByFoldedPhrase: [String: String] = commands.reduce(into: [:]) { table, entry in
        table[fold(entry.key)] = entry.value
        table[entry.key] = entry.value
    }

    private static func fold(_ text: String) -> String {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "pt_PT"))
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }

    func apply(to text: String) -> String {
        guard let pattern = Self.pattern, !text.isEmpty else { return text }
        let source = text as NSString
        var output = ""
        var consumed = 0
        for match in pattern.matches(in: text, range: NSRange(location: 0, length: source.length)) {
            output += source.substring(with: NSRange(location: consumed, length: match.range.location - consumed))
            consumed = match.range.location + match.range.length
            // A determiner preceded it: the speaker meant the word, keep it.
            if match.range(at: 1).location != NSNotFound {
                output += source.substring(with: match.range)
                continue
            }
            let phrase = Self.fold(source.substring(with: match.range(at: 2)))
            output += Self.symbolsByFoldedPhrase[phrase] ?? source.substring(with: match.range)
        }
        output += source.substring(from: consumed)
        return output
    }
}
