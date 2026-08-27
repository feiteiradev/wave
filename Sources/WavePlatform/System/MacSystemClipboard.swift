import AppKit
import WaveCore

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
}
