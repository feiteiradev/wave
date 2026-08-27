import Carbon.HIToolbox
import Foundation
import WaveCore

/// Registers Wave's two global hotkeys (PRD §14).
///
/// Uses Carbon's `RegisterEventHotKey` rather than a `CGEventTap` for two
/// reasons: it reports key-*release* as well as key-press, which push-to-talk
/// needs, and it does not require Input Monitoring on top of the two
/// permissions the PRD already asks for (PRD §31.1). Hotkeys registered this
/// way fire while any other application is focused.
public final class GlobalHotkeyMonitor: @unchecked Sendable {
    public struct Registration {
        let mode: DictationMode
        let binding: HotkeyBinding
    }

    private struct Installed {
        var reference: EventHotKeyRef?
        var mode: DictationMode
    }

    private let lock = NSLock()
    private var installed: [UInt32: Installed] = [:]
    private var eventHandler: EventHandlerRef?
    private var nextIdentifier: UInt32 = 1

    private let onPressed: @Sendable (DictationMode) -> Void
    private let onReleased: @Sendable (DictationMode) -> Void

    private static let signature = OSType(0x57415645) // 'WAVE'

    public init(
        onPressed: @escaping @Sendable (DictationMode) -> Void,
        onReleased: @escaping @Sendable (DictationMode) -> Void
    ) {
        self.onPressed = onPressed
        self.onReleased = onReleased
    }

    deinit {
        unregisterAll()
        if let eventHandler { RemoveEventHandler(eventHandler) }
    }

    /// Replaces the current registrations with `registrations`.
    ///
    /// Returns the modes that could not be registered — usually because another
    /// application already owns that combination.
    @discardableResult
    public func register(_ registrations: [Registration]) -> [DictationMode] {
        unregisterAll()
        installEventHandlerIfNeeded()

        var failed: [DictationMode] = []
        for registration in registrations {
            lock.lock()
            let identifier = nextIdentifier
            nextIdentifier += 1
            lock.unlock()

            var reference: EventHotKeyRef?
            let hotKeyID = EventHotKeyID(signature: Self.signature, id: identifier)
            let status = RegisterEventHotKey(
                registration.binding.keyCode,
                Self.carbonModifiers(registration.binding.modifiers),
                hotKeyID,
                GetEventDispatcherTarget(),
                0,
                &reference
            )
            if status == noErr, reference != nil {
                lock.lock()
                installed[identifier] = Installed(reference: reference, mode: registration.mode)
                lock.unlock()
            } else {
                failed.append(registration.mode)
            }
        }
        return failed
    }

    public func unregisterAll() {
        lock.lock()
        let references = installed.values.compactMap(\.reference)
        installed.removeAll()
        lock.unlock()
        for reference in references { UnregisterEventHotKey(reference) }
    }

    private func installEventHandlerIfNeeded() {
        guard eventHandler == nil else { return }
        var eventTypes = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased)),
        ]
        let context = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(
            GetEventDispatcherTarget(),
            { _, event, userData in
                guard let event, let userData else { return OSStatus(eventNotHandledErr) }
                let monitor = Unmanaged<GlobalHotkeyMonitor>.fromOpaque(userData).takeUnretainedValue()
                return monitor.handle(event)
            },
            eventTypes.count,
            &eventTypes,
            context,
            &eventHandler
        )
    }

    private func handle(_ event: EventRef) -> OSStatus {
        var hotKeyID = EventHotKeyID()
        let status = GetEventParameter(
            event,
            EventParamName(kEventParamDirectObject),
            EventParamType(typeEventHotKeyID),
            nil,
            MemoryLayout<EventHotKeyID>.size,
            nil,
            &hotKeyID
        )
        guard status == noErr, hotKeyID.signature == Self.signature else {
            return OSStatus(eventNotHandledErr)
        }

        lock.lock()
        let mode = installed[hotKeyID.id]?.mode
        lock.unlock()
        guard let mode else { return OSStatus(eventNotHandledErr) }

        switch Int(GetEventKind(event)) {
        case kEventHotKeyPressed: onPressed(mode)
        case kEventHotKeyReleased: onReleased(mode)
        default: return OSStatus(eventNotHandledErr)
        }
        return noErr
    }

    static func carbonModifiers(_ modifiers: HotkeyBinding.Modifiers) -> UInt32 {
        var result: UInt32 = 0
        if modifiers.contains(.command) { result |= UInt32(cmdKey) }
        if modifiers.contains(.shift) { result |= UInt32(shiftKey) }
        if modifiers.contains(.option) { result |= UInt32(optionKey) }
        if modifiers.contains(.control) { result |= UInt32(controlKey) }
        return result
    }
}
