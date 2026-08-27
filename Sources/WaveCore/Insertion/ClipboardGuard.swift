import Foundation

/// An opaque capture of the whole clipboard.
///
/// Wave has to put back exactly what it found, and what it finds is often not
/// text: an image, a file, several flavours of the same content. Snapshotting
/// only the string would silently destroy the rest (PRD §22.4).
public protocol ClipboardSnapshot: Sendable {}

/// The clipboard Wave writes to. Abstracted so the restore rules can be tested
/// without touching the real `NSPasteboard`.
public protocol SystemClipboard: AnyObject, Sendable {
    var stringContents: String? { get }
    func setStringContents(_ value: String?)
    /// Captures everything currently on the clipboard, in every flavour.
    func snapshot() -> any ClipboardSnapshot
    /// Puts a previous capture back.
    func restore(_ snapshot: any ClipboardSnapshot)
}

/// Borrows the clipboard for the transcription and gives it back safely
/// (PRD §22.3, §22.4).
///
/// The restore is conditional: if the user copied anything at all while Wave's
/// text was parked there, Wave leaves the clipboard alone. Overwriting whatever
/// the user just copied would be worse than leaving a stale transcription
/// behind.
public final class ClipboardGuard: @unchecked Sendable {
    private let clipboard: any SystemClipboard
    private let lock = NSLock()
    private var parkedText: String?
    private var previousContents: (any ClipboardSnapshot)?

    public init(clipboard: any SystemClipboard) {
        self.clipboard = clipboard
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
            previousContents = clipboard.snapshot()
        }
        parkedText = text
        clipboard.setStringContents(text)
    }

    /// Restores the saved clipboard, but only if the clipboard still holds
    /// exactly what Wave put there.
    @discardableResult
    public func restoreIfUnchanged() -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard let parkedText, let previousContents else { return false }
        guard clipboard.stringContents == parkedText else {
            // The user copied something else. Stand down and forget.
            self.parkedText = nil
            self.previousContents = nil
            return false
        }
        clipboard.restore(previousContents)
        self.parkedText = nil
        self.previousContents = nil
        return true
    }

    /// Drops the pending restore without touching the clipboard.
    ///
    /// Only correct when the caller knows the clipboard is already where it
    /// should be — otherwise use `restoreIfUnchanged()`, or the transcription
    /// is left behind and the next `place()` snapshots *it* as the contents to
    /// restore later.
    public func abandon() {
        lock.lock(); defer { lock.unlock() }
        parkedText = nil
        previousContents = nil
    }

    /// The final rung of the chain: always succeeds, so the transcription is
    /// never lost (PRD §23).
    public struct InsertionStrategy: TextInsertionStrategy {
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
}

/// Kept as a top-level name for call sites that read better without nesting.
public typealias ClipboardInsertionStrategy = ClipboardGuard.InsertionStrategy
