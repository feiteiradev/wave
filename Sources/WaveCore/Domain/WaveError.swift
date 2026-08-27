import Foundation

/// The short, specific errors the HUD is allowed to show (PRD §29).
///
/// Detail belongs in diagnostics, not on screen, so each case renders to one
/// terse line and nothing more.
public enum WaveError: String, Error, Sendable, Equatable, CaseIterable {
    case microphoneUnavailable
    case transcriptionFailed
    case modelUnavailable
    case insertionFailed

    public var hudMessage: String {
        switch self {
        case .microphoneUnavailable: "Microphone unavailable"
        case .transcriptionFailed: "Transcription failed"
        case .modelUnavailable: "Model unavailable"
        case .insertionFailed: "Insertion failed"
        }
    }
}
