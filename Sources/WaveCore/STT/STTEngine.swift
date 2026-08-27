import Foundation

/// A recording handed to the STT engine. Samples are mono float PCM in memory
/// (PRD §11.2) and are discarded as soon as transcription completes (PRD §21).
public struct AudioBuffer: Sendable {
    public var samples: [Float]
    public var sampleRate: Double
    /// Human-readable name of the capture device, for diagnostics only.
    public var deviceName: String

    public init(samples: [Float], sampleRate: Double, deviceName: String = "System Default") {
        self.samples = samples
        self.sampleRate = sampleRate
        self.deviceName = deviceName
    }

    public var duration: Double {
        sampleRate > 0 ? Double(samples.count) / sampleRate : 0
    }
}

/// Speech recognition, kept behind a protocol so the model and runtime can be
/// swapped without touching the rest of Wave (PRD §39, §47.7).
public protocol STTEngine: Sendable {
    /// Identifier written to diagnostics, e.g. `whisperkit/large-v3`.
    var identifier: String { get }
    /// Loads the model. Called before the first transcription.
    func prepare() async throws
    /// Transcribes one chunk. `hotwords` are vocabulary hints; engines that do
    /// not support biasing may ignore them (PRD §19.1).
    func transcribe(_ buffer: AudioBuffer, language: String, hotwords: [String]) async throws -> String
}

/// Natural-language cleanup, optional by design (PRD §8).
public protocol CleanupEngine: Sendable {
    var identifier: String { get }
    /// False when no cleanup model is installed — Clean then stops at the
    /// deterministic rules (PRD AC8).
    func isAvailable() async -> Bool
    func clean(_ text: String, language: String) async throws -> String
    /// Called when the idle timeout expires (PRD §8.1).
    func unload() async
}

/// Captures microphone audio into memory.
public protocol AudioRecording: Sendable {
    /// Begins capture. `onLevel` feeds the HUD waveform (PRD §27).
    func start(
        microphoneUniqueID: String?,
        onLevel: @escaping @Sendable (Float) -> Void
    ) async throws
    /// Stops capture and returns everything recorded.
    func stop() async -> AudioBuffer
    /// Abandons capture without producing a buffer.
    func cancel() async
}
