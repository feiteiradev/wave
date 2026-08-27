import Foundation
import WaveCore
import WhisperKit

/// Local speech recognition on top of WhisperKit's Core ML models.
///
/// Everything runs on-device: the model folder is loaded from
/// `~/Library/Application Support/Wave/Models/speech/…` and no request leaves
/// the Mac during dictation (PRD §9.1, §20.1).
public actor WhisperKitSTTEngine: STTEngine {
    public nonisolated let identifier: String

    private let modelFolder: URL
    private let variant: String
    private var whisperKit: WhisperKit?

    public init(modelFolder: URL, variant: String) {
        self.modelFolder = modelFolder
        self.variant = variant
        self.identifier = "whisperkit/\(variant)"
    }

    public func prepare() async throws {
        guard whisperKit == nil else { return }
        let configuration = WhisperKitConfig(
            model: variant,
            modelFolder: modelFolder.path,
            verbose: false,
            logLevel: .error,
            load: true,
            download: false
        )
        do {
            whisperKit = try await WhisperKit(configuration)
        } catch {
            throw WaveError.modelUnavailable
        }
    }

    public func transcribe(_ buffer: CapturedAudio, language: String, hotwords: [String]) async throws -> String {
        try await prepare()
        guard let whisperKit else { throw WaveError.modelUnavailable }
        guard !buffer.samples.isEmpty else { return "" }

        var options = DecodingOptions()
        // One language at a time, chosen by the user; no auto-detection (PRD §10).
        options.language = Self.whisperLanguageCode(for: language)
        options.detectLanguage = false
        options.task = .transcribe
        options.withoutTimestamps = true
        // Wave chunks the audio itself so it can cut on silence (PRD §11.3).
        options.chunkingStrategy = .none

        // Vocabulary as a decoder prompt — Whisper's supported form of hotword
        // biasing (PRD §19.1).
        if !hotwords.isEmpty, let tokenizer = whisperKit.tokenizer {
            let prompt = hotwords.joined(separator: ", ")
            let tokens = tokenizer.encode(text: " \(prompt)")
                .filter { $0 < tokenizer.specialTokens.specialTokenBegin }
            if !tokens.isEmpty {
                options.promptTokens = tokens
                options.usePrefillPrompt = true
            }
        }

        do {
            let results = try await whisperKit.transcribe(
                audioArray: buffer.samples,
                decodeOptions: options
            )
            return results
                .map(\.text)
                .joined(separator: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            throw WaveError.transcriptionFailed
        }
    }

    /// Whisper takes a bare language code; regional variants are not distinct
    /// models. `pt-PT` and `pt-BR` both decode as `pt` — the PT-PT quality
    /// comes from the model choice and the vocabulary, not this code.
    static func whisperLanguageCode(for bcp47: String) -> String {
        String(bcp47.split(separator: "-").first ?? "pt").lowercased()
    }
}
