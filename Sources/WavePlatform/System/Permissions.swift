import AVFoundation
import AppKit
import ApplicationServices

/// The two permissions Wave actually needs (PRD §31.1).
public enum Permission: String, Sendable, CaseIterable {
    case microphone
    case accessibility

    public var title: String {
        switch self {
        case .microphone: "Microphone"
        case .accessibility: "Accessibility"
        }
    }

    /// Shown before sending the user to System Settings (PRD §31.1).
    public var explanation: String {
        switch self {
        case .microphone:
            "Wave records your voice only while you hold the dictation hotkey. Audio stays on this Mac and is never saved."
        case .accessibility:
            "Wave needs Accessibility to type the transcription into whichever app you are using. Without it, text is copied to the clipboard instead."
        }
    }

    public var settingsURL: URL {
        switch self {
        case .microphone:
            URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!
        case .accessibility:
            URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        }
    }
}

public enum Permissions {
    public static func isGranted(_ permission: Permission) -> Bool {
        switch permission {
        case .microphone:
            AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        case .accessibility:
            AXIsProcessTrusted()
        }
    }

    /// Asks for microphone access. Accessibility cannot be granted in-process —
    /// the user must flip it in System Settings.
    public static func request(_ permission: Permission) async -> Bool {
        switch permission {
        case .microphone:
            return await AVCaptureDevice.requestAccess(for: .audio)
        case .accessibility:
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
            return AXIsProcessTrustedWithOptions(options as CFDictionary)
        }
    }

    @MainActor
    public static func openSettings(for permission: Permission) {
        NSWorkspace.shared.open(permission.settingsURL)
    }
}
