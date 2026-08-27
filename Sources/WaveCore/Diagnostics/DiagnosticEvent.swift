import Foundation

/// Everything Wave is allowed to write to its logs (PRD §37).
///
/// This is a closed enum of typed cases rather than a free-form string on
/// purpose: PRD §37.1 forbids audio, transcribed text, clipboard contents and
/// any personal content in the logs, and the cheapest way to guarantee that is
/// to make it unrepresentable. Sizes and durations are metadata; the text
/// itself never has a way in.
public enum DiagnosticEvent: Sendable, Equatable {
    case recordingStarted(microphone: String, mode: DictationMode)
    case recordingFinished(durationSeconds: Double)
    case noSpeechDetected
    case transcriptionStarted(model: String, chunks: Int)
    case transcriptionFinished(durationSeconds: Double, characterCount: Int)
    case cleanupSkipped(reason: CleanupSkipReason)
    case cleanupFinished(engine: String, durationSeconds: Double)
    case modelLoaded(id: String, loadSeconds: Double)
    case modelUnloaded(id: String)
    case modelDownloadStarted(id: String)
    case modelDownloadFinished(id: String, bytes: Int64)
    case modelDownloadFailed(id: String, willRetry: Bool)
    case inserted(method: InsertionMethod)
    /// A rung reported success but the app never showed the text, so the chain
    /// moved on. Counts only — the text itself still has no way in.
    case insertionDeclined(
        method: InsertionMethod,
        before: Int,
        expected: Int,
        after: Int,
        waitedMilliseconds: Int
    )
    case clipboardRestored(restored: Bool)
    case activationIgnored
    case failed(WaveError)

    public enum CleanupSkipReason: String, Sendable, Equatable {
        case rawMode
        case noModelInstalled
        case disabled
    }

    public var message: String {
        switch self {
        case let .recordingStarted(microphone, mode):
            "Recording started mode=\(mode.rawValue) microphone=\(microphone)"
        case let .recordingFinished(duration):
            "Recording duration: \(Self.seconds(duration))"
        case .noSpeechDetected:
            "No speech detected; dictation cancelled"
        case let .transcriptionStarted(model, chunks):
            "STT started model=\(model) chunks=\(chunks)"
        case let .transcriptionFinished(duration, characterCount):
            "STT duration: \(Self.seconds(duration)) characters=\(characterCount)"
        case let .cleanupSkipped(reason):
            "Cleanup skipped reason=\(reason.rawValue)"
        case let .cleanupFinished(engine, duration):
            "Cleanup duration: \(Self.seconds(duration)) engine=\(engine)"
        case let .modelLoaded(id, loadSeconds):
            "Model loaded id=\(id) load=\(Self.seconds(loadSeconds))"
        case let .modelUnloaded(id):
            "Model unloaded id=\(id)"
        case let .modelDownloadStarted(id):
            "Model download started id=\(id)"
        case let .modelDownloadFinished(id, bytes):
            "Model download finished id=\(id) bytes=\(bytes)"
        case let .modelDownloadFailed(id, willRetry):
            "Model download failed id=\(id) willRetry=\(willRetry)"
        case let .inserted(method):
            "Insertion: \(method.rawValue)"
        case let .insertionDeclined(method, before, expected, after, waited):
            "Insertion declined: \(method.rawValue) length before=\(before) expected=\(expected) "
                + "after=\(after) waited=\(waited)ms"
        case let .clipboardRestored(restored):
            "Clipboard restore: \(restored ? "restored" : "skipped, changed by user")"
        case .activationIgnored:
            "Activation ignored; a dictation is already in progress"
        case let .failed(error):
            "Error: \(error.rawValue)"
        }
    }

    private static func seconds(_ value: Double) -> String {
        String(format: "%.1fs", value)
    }
}
