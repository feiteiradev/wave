import Foundation

/// Deterministic, meaning-preserving cleanup (PRD §7.2, §8).
///
/// This is the whole of Clean when no cleanup LLM is installed (PRD AC8), and
/// the pre-pass that runs before the LLM when one is. Every rule here is
/// mechanical: spacing, punctuation adjacency, sentence capitalization. Rules
/// that require understanding — filler removal, restructuring, number and date
/// normalization — belong to the LLM, not here.
public struct CleanupRules: Sendable {
    public init() {}

    private static let sentenceTerminators: Set<Character> = [".", "!", "?", "…"]
    private static let closingPunctuation: Set<Character> = [",", ".", "!", "?", ";", ":", "…", "%"]

    public func apply(to text: String) -> String {
        var result = collapseWhitespace(text)
        guard !result.isEmpty else { return "" }
        result = tightenPunctuation(result)
        result = collapseImmediateRepetitions(result)
        result = capitalizeSentences(result)
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Runs of spaces/tabs collapse to one. Blank lines collapse to a single
    /// paragraph break — dictated text has no meaningful double blank lines.
    private func collapseWhitespace(_ text: String) -> String {
        let paragraphs = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .components(separatedBy: "\n")
            .map { $0.split(whereSeparator: \.isWhitespace).joined(separator: " ") }

        var lines: [String] = []
        for paragraph in paragraphs {
            if paragraph.isEmpty && lines.last?.isEmpty != false { continue }
            lines.append(paragraph)
        }
        while lines.last?.isEmpty == true { lines.removeLast() }
        return lines.joined(separator: "\n")
    }

    /// Removes the space STT often leaves before `,` `.` `?` and friends, and
    /// guarantees one space after them when a word follows.
    private func tightenPunctuation(_ text: String) -> String {
        var output = ""
        output.reserveCapacity(text.count)
        var characters = Array(text)
        var index = 0
        while index < characters.count {
            let character = characters[index]
            if Self.closingPunctuation.contains(character) {
                while output.last == " " { output.removeLast() }
                output.append(character)
                // Don't split "3.14" or "10:30" — only space out prose.
                let next = index + 1 < characters.count ? characters[index + 1] : nil
                let previous = output.dropLast().last
                let betweenDigits = (previous?.isNumber ?? false) && (next?.isNumber ?? false)
                if let next, next != " ", !betweenDigits,
                   !Self.closingPunctuation.contains(next), next != "\n" {
                    output.append(" ")
                }
                index += 1
                continue
            }
            output.append(character)
            index += 1
        }
        characters = []
        return output
    }

    /// `o o carro` → `o carro`. STT stutters on short function words; this only
    /// touches an adjacent identical pair, never a legitimate repeat across a
    /// sentence boundary.
    private func collapseImmediateRepetitions(_ text: String) -> String {
        text.components(separatedBy: "\n").map { line -> String in
            var kept: [Substring] = []
            for word in line.split(separator: " ", omittingEmptySubsequences: true) {
                if let previous = kept.last,
                   previous.caseInsensitiveCompare(String(word)) == .orderedSame,
                   word.allSatisfy({ $0.isLetter }) {
                    continue
                }
                kept.append(word)
            }
            return kept.joined(separator: " ")
        }.joined(separator: "\n")
    }

    /// Uppercases the first letter of the text and of anything following a
    /// sentence terminator.
    private func capitalizeSentences(_ text: String) -> String {
        var output: [Character] = []
        output.reserveCapacity(text.count)
        var capitalizeNext = true
        for character in text {
            if capitalizeNext, character.isLetter {
                output.append(contentsOf: String(character).uppercased())
                capitalizeNext = false
                continue
            }
            if Self.sentenceTerminators.contains(character) || character == "\n" {
                capitalizeNext = true
            } else if !character.isWhitespace && !Self.closingPunctuation.contains(character) {
                capitalizeNext = false
            }
            output.append(character)
        }
        return String(output)
    }
}
