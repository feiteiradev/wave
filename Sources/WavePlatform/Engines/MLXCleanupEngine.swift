import Foundation
import MLXLLM
import MLXLMCommon
import WaveCore

/// Optional natural-language cleanup with a local LLM on MLX (PRD §7.2, §8).
///
/// The model is loaded on first use and unloaded again after a period of
/// inactivity, so a multi-gigabyte model does not sit in RAM between
/// dictations (PRD §8.1).
public actor MLXCleanupEngine: CleanupEngine {
    public nonisolated let identifier: String

    private let modelDirectory: URL
    private let idleUnloadSeconds: Double
    private let logger: DiagnosticsLogger?
    private var container: ModelContainer?
    private var unloadTask: Task<Void, Never>?

    public init(
        modelDirectory: URL,
        modelID: String,
        idleUnloadSeconds: Double = 180,
        logger: DiagnosticsLogger? = nil
    ) {
        self.modelDirectory = modelDirectory
        self.identifier = "mlx/\(modelID)"
        self.idleUnloadSeconds = idleUnloadSeconds
        self.logger = logger
    }

    public func isAvailable() async -> Bool {
        FileManager.default.fileExists(atPath: modelDirectory.path)
    }

    public func clean(_ text: String, language: String) async throws -> String {
        guard !text.isEmpty else { return text }
        let container = try await loadedContainer()
        scheduleUnload()

        // A fresh session per dictation: Wave keeps no conversation and no
        // memory of what was said (PRD §21).
        let session = ChatSession(
            container,
            instructions: Self.instructions(for: language),
            generateParameters: GenerateParameters(maxTokens: Self.maxOutputTokens, temperature: 0.2)
        )
        let output = try await session.respond(to: text)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // A model that ignores the instruction and answers something else must
        // not replace the user's words (PRD §7.2: meaning is never changed).
        return output.isEmpty ? text : output
    }

    public func unload() async {
        unloadTask?.cancel()
        unloadTask = nil
        if container != nil {
            container = nil
            logger?.log(.modelUnloaded(id: identifier))
        }
    }

    private func loadedContainer() async throws -> ModelContainer {
        if let container { return container }
        let started = Date()
        let configuration = ModelConfiguration(directory: modelDirectory)
        let container = try await loadModelContainer(configuration: configuration)
        self.container = container
        logger?.log(.modelLoaded(id: identifier, loadSeconds: Date().timeIntervalSince(started)))
        return container
    }

    private func scheduleUnload() {
        unloadTask?.cancel()
        let seconds = idleUnloadSeconds
        unloadTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(max(1, seconds) * 1_000_000_000))
            guard !Task.isCancelled else { return }
            await self?.unload()
        }
    }

    /// Roughly four times the length of a long dictation, so a valid tidy-up
    /// is never truncated but a runaway generation still terminates.
    static let maxOutputTokens = 2_048

    /// The cleanup instruction (PRD §7.2). Deliberately narrow: the model is
    /// asked to tidy, never to answer, summarize or continue.
    static func instructions(for language: String) -> String {
        """
        You are a transcription editor. Every message you receive is text that \
        was dictated aloud in \(languageName(for: language)) and transcribed \
        automatically.

        Rewrite it with correct punctuation, capitalization and paragraph \
        breaks. Remove filler words and accidental repetitions. Normalize \
        numbers, dates and times. Correct obvious transcription errors.

        Rules you must not break:
        - Never change the meaning, and never add information.
        - Never answer, summarize, translate or continue the text.
        - Keep the original language.
        - Reply with the corrected text only, with no preamble or quotes.
        """
    }

    static func languageName(for bcp47: String) -> String {
        Locale(identifier: "en_US").localizedString(forIdentifier: bcp47.replacingOccurrences(of: "-", with: "_"))
            ?? bcp47
    }
}
