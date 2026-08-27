import AppKit
import WaveCore

/// Everything that was on the pasteboard, in every flavour it was offered.
struct PasteboardSnapshot: ClipboardSnapshot, @unchecked Sendable {
    let items: [NSPasteboardItem]
}

/// `NSPasteboard.general` behind the core's `SystemClipboard` protocol.
public final class MacSystemClipboard: SystemClipboard, @unchecked Sendable {
    private let pasteboard: NSPasteboard

    public init(pasteboard: NSPasteboard = .general) {
        self.pasteboard = pasteboard
    }

    public var stringContents: String? {
        pasteboard.string(forType: .string)
    }

    public func setStringContents(_ value: String?) {
        pasteboard.clearContents()
        if let value {
            pasteboard.setString(value, forType: .string)
        }
    }

    /// `NSPasteboardItem`s belong to the pasteboard that vended them, so each
    /// one is copied into a fresh item before the pasteboard is cleared.
    public func snapshot() -> any ClipboardSnapshot {
        let copies = (pasteboard.pasteboardItems ?? []).map { item -> NSPasteboardItem in
            let copy = NSPasteboardItem()
            for type in item.types {
                if let data = item.data(forType: type) {
                    copy.setData(data, forType: type)
                }
            }
            return copy
        }
        return PasteboardSnapshot(items: copies)
    }

    public func restore(_ snapshot: any ClipboardSnapshot) {
        guard let snapshot = snapshot as? PasteboardSnapshot else { return }
        pasteboard.clearContents()
        guard !snapshot.items.isEmpty else { return }
        pasteboard.writeObjects(snapshot.items)
    }
}
