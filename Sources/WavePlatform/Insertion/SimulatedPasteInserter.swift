import AppKit
import WaveCore

/// Second rung: put the text on the clipboard and synthesize ⌘V (PRD §22.2).
///
/// The clipboard borrow is guarded exactly like the fallback rung — if the
/// paste works, the user's previous clipboard is put back after the retention
/// period, and only if they have not copied something else since (PRD §22.4).
public struct SimulatedPasteInserter: TextInsertionStrategy {
    public let method: InsertionMethod = .simulatedPaste

    private let guardian: ClipboardGuard
    /// Time for the target app to service the paste before we consider it done.
    private let pasteSettleSeconds: Double

    public init(guardian: ClipboardGuard, pasteSettleSeconds: Double = 0.12) {
        self.guardian = guardian
        self.pasteSettleSeconds = pasteSettleSeconds
    }

    public func insert(_ text: String) async throws -> Bool {
        // Synthesizing key events needs the same trust as Accessibility.
        // Refuse when nothing can receive the paste, so the clipboard rung —
        // and its toast — still runs (PRD §23).
        guard let element = FocusedTextElement.current(),
              FocusedTextElement.acceptsText(element),
              let source = CGEventSource(stateID: .combinedSessionState)
        else { return false }

        guardian.place(text)

        let commandV: CGKeyCode = 9 // kVK_ANSI_V
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: commandV, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: commandV, keyDown: false)
        else {
            // Put the clipboard back before declining, so the fallback rung
            // snapshots the user's contents rather than this transcription.
            guardian.restoreIfUnchanged()
            return false
        }
        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)

        try? await Task.sleep(nanoseconds: UInt64(pasteSettleSeconds * 1_000_000_000))
        return true
    }
}
