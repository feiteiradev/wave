import Foundation

/// The clipboard Wave writes to. Abstracted so the restore rules can be tested
/// without touching the real `NSPasteboard`.
public protocol Pasteboard: AnyObject, Sendable {
    var stringContents: String? { get }
    func setStringContents(_ value: String?)
}

/// Borrows the clipboard for the transcription and gives it back safely
/// (PRD §22.3, §22.4).
///
/// The restore is conditional: if the user copied anything at all while Wave's
/// text was parked there, Wave leaves the clipboard alone. Overwriting whatever
/// the user just copied would be worse than leaving a stale transcription
/// behind.
public final class ClipboardGuard: @unchecked Sendable {
    private let pasteboard: any Pasteboard
    private let lock = NSLock()
    private var parkedText: String?
    private var previousContents: String?

    public init(pasteboard: any Pasteboard) {
        self.pasteboard = pasteboard
    }

    /// True while Wave has text parked on the clipboard awaiting restore.
    public var isHoldingClipboard: Bool {
        lock.lock(); defer { lock.unlock() }
        return parkedText != nil
    }

    /// Saves the current clipboard and puts `text` there.
    public func place(_ text: String) {
        lock.lock(); defer { lock.unlock() }
        // A second dictation before the first restore: keep the *original*
        // contents, not Wave's own previous transcription.
        if parkedText == nil {
            previousContents = pasteboard.stringContents
        }
        parkedText = text
        pasteboard.setStringContents(text)
    }

    /// Restores the saved clipboard, but only if the clipboard still holds
    /// exactly what Wave put there.
    @discardableResult
    public func restoreIfUnchanged() -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard let parkedText else { return false }
        guard pasteboard.stringContents == parkedText else {
            // The user copied something else. Stand down and forget.
            self.parkedText = nil
            self.previousContents = nil
            return false
        }
        pasteboard.setStringContents(previousContents)
        self.parkedText = nil
        self.previousContents = nil
        return true
    }

    /// Drops the pending restore without touching the clipboard.
    public func abandon() {
        lock.lock(); defer { lock.unlock() }
        parkedText = nil
        previousContents = nil
    }
}

/// The final rung of the chain: always succeeds, so the transcription is never
/// lost (PRD §23).
public struct ClipboardInsertionStrategy: TextInsertionStrategy {
    public let method: InsertionMethod = .clipboard
    private let guardian: ClipboardGuard

    public init(guardian: ClipboardGuard) {
        self.guardian = guardian
    }

    public func insert(_ text: String) async throws -> Bool {
        guardian.place(text)
        return true
    }
}
