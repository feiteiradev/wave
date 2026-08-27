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

    public init() {}

    public func insert(_ text: String) async throws -> Bool {
        guard AXIsProcessTrusted() else { return false }

        let system = AXUIElementCreateSystemWide()
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            system,
            kAXFocusedUIElementAttribute as CFString,
            &focused
        ) == .success, let focusedElement = focused else { return false }

        let element = focusedElement as! AXUIElement

        // Prefer replacing just the selection: that preserves the caret
        // position and anything already typed around it (PRD §22.1).
        if isSettable(element, attribute: kAXSelectedTextAttribute) {
            let status = AXUIElementSetAttributeValue(
                element,
                kAXSelectedTextAttribute as CFString,
                text as CFTypeRef
            )
            if status == .success { return true }
        }

        // Otherwise append to the whole value, keeping what is already there.
        guard isSettable(element, attribute: kAXValueAttribute) else { return false }
        var existing: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &existing)
        let current = (existing as? String) ?? ""
        let status = AXUIElementSetAttributeValue(
            element,
            kAXValueAttribute as CFString,
            (current + text) as CFTypeRef
        )
        return status == .success
    }

    private func isSettable(_ element: AXUIElement, attribute: String) -> Bool {
        var settable: DarwinBoolean = false
        let status = AXUIElementIsAttributeSettable(element, attribute as CFString, &settable)
        return status == .success && settable.boolValue
    }
}
