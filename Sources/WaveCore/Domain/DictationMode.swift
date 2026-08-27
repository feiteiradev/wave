import Foundation

/// The two dictation modes described in PRD §7.
public enum DictationMode: String, Codable, Sendable, CaseIterable {
    /// Minimal linguistic transformation: STT → vocabulary → output.
    case raw
    /// STT → vocabulary → deterministic rules → optional local LLM → output.
    case clean
}

/// How a hotkey activation maps to recording start/stop (PRD §13).
public enum ActivationMode: String, Codable, Sendable, CaseIterable {
    case pushToTalk
    case toggle
}
