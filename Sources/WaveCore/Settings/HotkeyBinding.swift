import Foundation

/// A global hotkey as stored in preferences (PRD §14).
///
/// Carbon virtual key code plus modifier mask, kept as plain data so the
/// binding can be persisted and shown in Settings without dragging AppKit into
/// the core.
public struct HotkeyBinding: Codable, Sendable, Hashable {
    public struct Modifiers: OptionSet, Codable, Sendable, Hashable {
        public let rawValue: UInt32
        public init(rawValue: UInt32) { self.rawValue = rawValue }
        public static let command = Modifiers(rawValue: 1 << 0)
        public static let option = Modifiers(rawValue: 1 << 1)
        public static let control = Modifiers(rawValue: 1 << 2)
        public static let shift = Modifiers(rawValue: 1 << 3)
    }

    public var keyCode: UInt32
    public var modifiers: Modifiers

    public init(keyCode: UInt32, modifiers: Modifiers) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    /// `kVK_Space`.
    public static let spaceKeyCode: UInt32 = 49

    /// ⌥ Space (PRD §14 example).
    public static let defaultClean = HotkeyBinding(keyCode: spaceKeyCode, modifiers: [.option])
    /// ⌥ ⇧ Space (PRD §14 example).
    public static let defaultRaw = HotkeyBinding(keyCode: spaceKeyCode, modifiers: [.option, .shift])

    public var displayString: String {
        var parts = ""
        if modifiers.contains(.control) { parts += "⌃" }
        if modifiers.contains(.option) { parts += "⌥" }
        if modifiers.contains(.shift) { parts += "⇧" }
        if modifiers.contains(.command) { parts += "⌘" }
        return parts + Self.keyName(for: keyCode)
    }

    static func keyName(for keyCode: UInt32) -> String {
        switch keyCode {
        case 49: "Space"
        case 36: "Return"
        case 48: "Tab"
        case 53: "Esc"
        default: Self.characters[keyCode] ?? "Key \(keyCode)"
        }
    }

    private static let characters: [UInt32: String] = [
        0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X", 8: "C", 9: "V",
        11: "B", 12: "Q", 13: "W", 14: "E", 15: "R", 16: "Y", 17: "T", 31: "O", 32: "U",
        34: "I", 35: "P", 37: "L", 38: "J", 40: "K", 45: "N", 46: "M",
    ]
}
