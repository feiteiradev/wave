import ApplicationServices

/// Locates the focused text element via the Accessibility API.
///
/// Shared by both direct-insertion rungs so they agree on what "there is
/// somewhere to type" means. Without this, simulated paste would report success
/// even with nothing focused, and the clipboard fallback — the rung that
/// guarantees the transcription is never lost — would be unreachable
/// (PRD §23).
enum FocusedTextElement {
    static func current() -> AXUIElement? {
        guard AXIsProcessTrusted() else { return nil }
        let system = AXUIElementCreateSystemWide()
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            system,
            kAXFocusedUIElementAttribute as CFString,
            &focused
        ) == .success, let focused else { return nil }
        return (focused as! AXUIElement)
    }

    /// True when the focused element looks like somewhere text can be typed.
    ///
    /// A settable text attribute is the strong signal. Some apps (Electron and
    /// other custom text views) expose neither while still accepting a paste,
    /// so a known text-ish role counts too.
    static func acceptsText(_ element: AXUIElement) -> Bool {
        if isSettable(element, attribute: kAXSelectedTextAttribute)
            || isSettable(element, attribute: kAXValueAttribute) {
            return true
        }
        var role: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &role) == .success,
              let roleName = role as? String
        else { return false }
        return textRoles.contains(roleName)
    }

    private static let textRoles: Set<String> = [
        kAXTextFieldRole as String,
        kAXTextAreaRole as String,
        kAXComboBoxRole as String,
        kAXSearchFieldSubrole as String,
        "AXWebArea",
    ]

    static func stringAttribute(_ element: AXUIElement, _ attribute: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value as? String
    }

    /// Length of the element's text in UTF-16 units — the unit the
    /// Accessibility API counts in. Used as the read-back signal: an AX set
    /// that returns .success but leaves this unchanged did nothing.
    static func characterCount(_ element: AXUIElement) -> Int? {
        var value: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXNumberOfCharactersAttribute as CFString, &value) == .success,
           let number = value as? Int {
            return number
        }
        return stringAttribute(element, kAXValueAttribute)?.utf16.count
    }

    /// How many characters the current selection covers, so a selection-replacing
    /// write knows what length to expect afterwards.
    static func selectedTextLength(_ element: AXUIElement) -> Int? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXValueGetTypeID()
        else { return nil }
        var range = CFRange()
        guard AXValueGetValue(value as! AXValue, .cfRange, &range) else { return nil }
        return range.length
    }

    static func isSettable(_ element: AXUIElement, attribute: String) -> Bool {
        var settable: DarwinBoolean = false
        let status = AXUIElementIsAttributeSettable(element, attribute as CFString, &settable)
        return status == .success && settable.boolValue
    }
}
