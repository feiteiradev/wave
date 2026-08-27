import Foundation

/// What the notch HUD is showing (PRD §26–§29).
public enum HUDState: Sendable, Equatable {
    case hidden
    /// `level` is a smoothed 0...1 amplitude driving the waveform (PRD §27).
    case recording(level: Float)
    case processing
    case done
    case error(WaveError)
    /// The clipboard-fallback toast (PRD §22.3).
    case toast(String)

    public var isVisible: Bool { self != .hidden }
}

/// The dictation pipeline's own state (PRD §15).
public enum DictationState: Sendable, Equatable {
    case idle
    case recording(mode: DictationMode)
    case processing(mode: DictationMode)

    public var isBusy: Bool { self != .idle }
}
