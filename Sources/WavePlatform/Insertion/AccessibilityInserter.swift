import AppKit
import ApplicationServices
import WaveCore

/// First rung of the fallback chain: write straight into the focused text
/// element via the Accessibility API (PRD §22.1).
///
/// Returns `false` — rather than throwing — whenever the focused element is not
/// a settable text element, so the pipeline moves on to simulated paste.
public struct AccessibilityInserter: TextInsertionStrategy {
    public let method: InsertionMethod = .accessibility

    /// Read-back window. A write that landed shows up well inside it; a write
    /// the app dropped never shows up at all.
    private static let readBackWindow: TimeInterval = 0.2
    private static let readBackInterval: UInt64 = 15_000_000 // 15ms

    private let logger: DiagnosticsLogger?

    public init(logger: DiagnosticsLogger? = nil) {
        self.logger = logger
    }

    public func insert(_ text: String) async throws -> Bool {
        guard let element = FocusedTextElement.current() else { return false }
        let before = FocusedTextElement.characterCount(element)

        // Prefer replacing just the selection: that preserves the caret
        // position and anything already typed around it (PRD §22.1).
        if FocusedTextElement.isSettable(element, attribute: kAXSelectedTextAttribute) {
            // An unreadable selection length leaves nothing to predict, so the
            // write goes unverified rather than checked against a guess.
            let selected = FocusedTextElement.selectedTextLength(element)
            let status = AXUIElementSetAttributeValue(
                element,
                kAXSelectedTextAttribute as CFString,
                text as CFTypeRef
            )
            let expected: Int? = if let before, let selected {
                before - selected + text.utf16.count
            } else {
                nil
            }
            if status == .success, await landed(in: element, before: before, expected: expected) {
                return true
            }
        }

        // Otherwise append to the whole value, keeping what is already there.
        guard FocusedTextElement.isSettable(element, attribute: kAXValueAttribute) else { return false }
        var existing: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &existing)
        let current = (existing as? String) ?? ""
        let status = AXUIElementSetAttributeValue(
            element,
            kAXValueAttribute as CFString,
            (current + text) as CFTypeRef
        )
        guard status == .success else { return false }
        return await landed(
            in: element,
            before: current.utf16.count,
            expected: current.utf16.count + text.utf16.count
        )
    }

    /// Confirms the write actually happened, by watching the text length.
    ///
    /// A `.success` status is not proof: iTerm2 advertises a settable
    /// `AXValue` on its terminal view and silently drops the write. Believing
    /// the status stops the fallback chain at rung one, so the text reaches
    /// neither the app nor the clipboard (PRD §23, §42.1).
    ///
    /// The check has to wait, though. Chromium-based apps — Notion, Slack,
    /// Chrome — answer Accessibility reads from a cache the renderer refreshes
    /// a beat after the write, so an immediate read reports the old length for
    /// a write that did land. A landed write converges within the window; a
    /// dropped one never moves at all.
    ///
    /// Anything other than "the length never budged" counts as landed, and an
    /// unpredictable case is not checked at all. The bias is deliberate:
    /// claiming the wrong rung costs a log line, whereas falling through after
    /// a write that landed inserts the text twice.
    ///
    /// Lengths are UTF-16 units, the unit the Accessibility API counts in.
    /// Swift characters would mispredict every transcript holding an accent —
    /// with Portuguese as the primary language, most of them.
    private func landed(in element: AXUIElement, before: Int?, expected: Int?) async -> Bool {
        // No readable length, or a write whose result is indistinguishable
        // from the starting length (a selection replaced by text of the same
        // length): nothing to verify against.
        guard let before, let expected, expected != before else { return true }

        let started = Date()
        while Date().timeIntervalSince(started) < Self.readBackWindow {
            guard let after = FocusedTextElement.characterCount(element) else { return true }
            if after != before { return true }
            try? await Task.sleep(nanoseconds: Self.readBackInterval)
        }

        logger?.log(.insertionDeclined(
            method: method,
            before: before,
            expected: expected,
            after: FocusedTextElement.characterCount(element) ?? before,
            waitedMilliseconds: Int(Date().timeIntervalSince(started) * 1000)
        ))
        return false
    }
}
