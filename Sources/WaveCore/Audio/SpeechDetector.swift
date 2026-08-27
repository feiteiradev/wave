import Foundation

/// Decides whether a recording contains speech at all (PRD §16, AC7).
///
/// If it does not, the dictation is cancelled silently: no text, no clipboard
/// write, no toast. Any recording that *does* contain audio is processed no
/// matter how short — there is no artificial minimum duration (PRD §17).
public struct SpeechDetector: Sendable {
    /// RMS below this counts as silence. Roughly -50 dBFS.
    public let threshold: Float
    /// How much loud-enough audio must accumulate before it counts as speech.
    public let minimumVoicedSeconds: Double

    public init(threshold: Float = 0.003, minimumVoicedSeconds: Double = 0.08) {
        self.threshold = threshold
        self.minimumVoicedSeconds = minimumVoicedSeconds
    }

    public func containsSpeech(samples: [Float], sampleRate: Double) -> Bool {
        guard !samples.isEmpty, sampleRate > 0 else { return false }
        let window = max(1, Int(0.02 * sampleRate))
        let requiredWindows = max(1, Int((minimumVoicedSeconds * sampleRate) / Double(window)))

        var voicedWindows = 0
        var index = 0
        while index < samples.count {
            let end = min(index + window, samples.count)
            if rms(samples[index..<end]) > threshold {
                voicedWindows += 1
                if voicedWindows >= requiredWindows { return true }
            }
            index = end
        }
        return false
    }

    /// Normalized 0...1 level for the HUD waveform (PRD §27).
    public func level(samples: ArraySlice<Float>) -> Float {
        min(1, rms(samples) * 12)
    }

    private func rms(_ samples: ArraySlice<Float>) -> Float {
        guard !samples.isEmpty else { return 0 }
        var sum: Float = 0
        for sample in samples { sum += sample * sample }
        return (sum / Float(samples.count)).squareRoot()
    }
}
