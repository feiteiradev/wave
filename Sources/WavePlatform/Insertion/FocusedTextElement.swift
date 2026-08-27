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

    static func isSettable(_ element: AXUIElement, attribute: String) -> Bool {
        var settable: DarwinBoolean = false
        let status = AXUIElementIsAttributeSettable(element, attribute as CFString, &settable)
        return status == .success && settable.boolValue
    }
}
