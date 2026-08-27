import Foundation

/// How the final text reached the user (PRD §22). Recorded in diagnostics.
public enum InsertionMethod: String, Sendable, Equatable, CaseIterable {
    case accessibility
    case simulatedPaste
    case clipboard
}

/// One rung of the insertion fallback chain.
///
/// `insert` returns `false` when the strategy does not apply (no focused text
/// element, no Accessibility permission) — the pipeline then moves to the next
/// rung. Throwing is treated the same way: a rung that fails never aborts the
/// chain, because losing the transcription is the one unacceptable outcome
/// (PRD §42.1).
public protocol TextInsertionStrategy: Sendable {
    var method: InsertionMethod { get }
    func insert(_ text: String) async throws -> Bool
}

/// Walks the strategies in order and reports which one took the text.
///
/// The last strategy handed to the pipeline is expected to be the clipboard
/// fallback, which always succeeds; if every strategy declines, the pipeline
/// reports failure rather than silently dropping the text.
public struct InsertionPipeline: Sendable {
    private let strategies: [any TextInsertionStrategy]

    public init(strategies: [any TextInsertionStrategy]) {
        self.strategies = strategies
    }

    public func insert(_ text: String) async -> InsertionMethod? {
        guard !text.isEmpty else { return nil }
        for strategy in strategies {
            if (try? await strategy.insert(text)) == true {
                return strategy.method
            }
        }
        return nil
    }
}
