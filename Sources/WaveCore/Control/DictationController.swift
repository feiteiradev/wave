import Foundation

/// Drives one dictation from hotkey press to inserted text (PRD §6.1, §38).
///
/// Wave handles exactly one dictation at a time (PRD §15): an activation
/// arriving while a previous one is still processing is dropped on the floor,
/// with no error and no interruption to the HUD (PRD AC10).
public actor DictationController {
    public struct Environment: Sendable {
        public var recorder: any AudioRecording
        /// Resolves the active STT engine, or nil when no model is installed.
        public var speechEngine: @Sendable () async -> (any STTEngine)?
        /// Resolves the cleanup engine, or nil when none is installed (PRD §8).
        public var cleanupEngine: @Sendable () async -> (any CleanupEngine)?
        public var insertion: InsertionPipeline
        public var clipboard: ClipboardGuard
        public var preferences: @Sendable () -> Preferences
        public var logger: DiagnosticsLogger?
        public var scheduler: any Scheduler
        public var chunker: AudioChunker
        public var speechDetector: SpeechDetector
        public var rules: CleanupRules

        public init(
            recorder: any AudioRecording,
            speechEngine: @escaping @Sendable () async -> (any STTEngine)?,
            cleanupEngine: @escaping @Sendable () async -> (any CleanupEngine)?,
            insertion: InsertionPipeline,
            clipboard: ClipboardGuard,
            preferences: @escaping @Sendable () -> Preferences,
            logger: DiagnosticsLogger? = nil,
            scheduler: any Scheduler = TaskScheduler(),
            chunker: AudioChunker = AudioChunker(),
            speechDetector: SpeechDetector = SpeechDetector(),
            rules: CleanupRules = CleanupRules()
        ) {
            self.recorder = recorder
            self.speechEngine = speechEngine
            self.cleanupEngine = cleanupEngine
            self.insertion = insertion
            self.clipboard = clipboard
            self.preferences = preferences
            self.logger = logger
            self.scheduler = scheduler
            self.chunker = chunker
            self.speechDetector = speechDetector
            self.rules = rules
        }
    }

    public static let clipboardToastMessage = "Copied to clipboard"

    private let environment: Environment
    private var state: DictationState = .idle
    private var hud: HUDState = .hidden
    /// Bumped on every HUD change so a stale auto-hide cannot clear a newer state.
    private var hudGeneration = 0

    private var onStateChange: (@Sendable (DictationState) -> Void)?
    private var onHUDChange: (@Sendable (HUDState) -> Void)?

    public init(environment: Environment) {
        self.environment = environment
    }

    public func observe(
        state onStateChange: @escaping @Sendable (DictationState) -> Void,
        hud onHUDChange: @escaping @Sendable (HUDState) -> Void
    ) {
        self.onStateChange = onStateChange
        self.onHUDChange = onHUDChange
        onStateChange(state)
        onHUDChange(hud)
    }

    public var currentState: DictationState { state }
    public var currentHUD: HUDState { hud }

    // MARK: - Activation

    /// A dictation hotkey went down.
    public func hotkeyPressed(mode: DictationMode) async {
        switch environment.preferences().activationMode {
        case .pushToTalk:
            await beginRecording(mode: mode)
        case .toggle:
            if case let .recording(current) = state, current == mode {
                await finishRecording()
            } else {
                await beginRecording(mode: mode)
            }
        }
    }

    /// A dictation hotkey came up. Ignored in toggle mode.
    public func hotkeyReleased(mode: DictationMode) async {
        guard environment.preferences().activationMode == .pushToTalk else { return }
        guard case let .recording(current) = state, current == mode else { return }
        await finishRecording()
    }

    /// The menu-bar Start/Stop Recording item. Always behaves as a toggle and
    /// always starts a Clean dictation, whatever the hotkey mode is (PRD §25).
    public func menuBarToggle() async {
        if case .recording = state {
            await finishRecording()
        } else {
            await beginRecording(mode: .clean)
        }
    }

    // MARK: - Recording

    private func beginRecording(mode: DictationMode) async {
        guard state == .idle else {
            // One dictation at a time; the HUD keeps showing Processing (PRD §15).
            environment.logger?.log(.activationIgnored)
            return
        }
        let preferences = environment.preferences()
        setState(.recording(mode: mode))
        setHUD(.recording(level: 0))

        do {
            try await environment.recorder.start(microphoneUniqueID: preferences.microphoneUniqueID) { [weak self] level in
                Task { await self?.updateLevel(level) }
            }
            environment.logger?.log(.recordingStarted(
                microphone: preferences.microphoneUniqueID ?? "System Default",
                mode: mode
            ))
        } catch {
            await environment.recorder.cancel()
            fail(.microphoneUnavailable)
        }
    }

    private func updateLevel(_ level: Float) {
        guard case .recording = state else { return }
        setHUD(.recording(level: level))
    }

    private func finishRecording() async {
        guard case let .recording(mode) = state else { return }
        setState(.processing(mode: mode))
        setHUD(.processing)

        let buffer = await environment.recorder.stop()
        environment.logger?.log(.recordingFinished(durationSeconds: buffer.duration))

        guard environment.speechDetector.containsSpeech(
            samples: buffer.samples,
            sampleRate: buffer.sampleRate
        ) else {
            // No speech: cancel silently. No text, no clipboard, no toast (PRD §16).
            environment.logger?.log(.noSpeechDetected)
            setHUD(.hidden)
            setState(.idle)
            return
        }

        await process(buffer: buffer, mode: mode)
    }

    // MARK: - Pipeline

    private func process(buffer: AudioBuffer, mode: DictationMode) async {
        let preferences = environment.preferences()
        let vocabulary = VocabularyManager(terms: preferences.vocabulary)

        guard let engine = await environment.speechEngine() else {
            fail(.modelUnavailable)
            return
        }

        let transcript: String
        do {
            transcript = try await transcribe(
                buffer: buffer,
                engine: engine,
                language: preferences.language,
                hotwords: vocabulary.hotwords
            )
        } catch {
            fail(.transcriptionFailed)
            return
        }

        // Vocabulary belongs to recognition, so it runs for Raw too (PRD §7.1).
        var text = vocabulary.normalize(transcript)

        if mode == .clean {
            text = environment.rules.apply(to: text)
            text = await applyCleanupLLM(to: text, preferences: preferences)
        } else {
            environment.logger?.log(.cleanupSkipped(reason: .rawMode))
        }

        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            // The STT heard something but produced nothing usable — same
            // silent outcome as no speech.
            environment.logger?.log(.noSpeechDetected)
            setHUD(.hidden)
            setState(.idle)
            return
        }

        await insert(text, preferences: preferences)
    }

    private func transcribe(
        buffer: AudioBuffer,
        engine: any STTEngine,
        language: String,
        hotwords: [String]
    ) async throws -> String {
        let ranges = environment.chunker.chunkRanges(
            samples: buffer.samples,
            sampleRate: buffer.sampleRate
        )
        environment.logger?.log(.transcriptionStarted(model: engine.identifier, chunks: ranges.count))
        let started = Date()

        try await engine.prepare()

        // Chunks are transcribed in order and concatenated; from the user's
        // point of view this was always one dictation (PRD §11.3, AC6).
        var pieces: [String] = []
        for range in ranges {
            let chunk = AudioBuffer(
                samples: Array(buffer.samples[range]),
                sampleRate: buffer.sampleRate,
                deviceName: buffer.deviceName
            )
            let piece = try await engine.transcribe(chunk, language: language, hotwords: hotwords)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !piece.isEmpty { pieces.append(piece) }
        }

        let transcript = pieces.joined(separator: " ")
        environment.logger?.log(.transcriptionFinished(
            durationSeconds: Date().timeIntervalSince(started),
            characterCount: transcript.count
        ))
        return transcript
    }

    /// Clean's LLM pass. Optional by design: without a model, or if the model
    /// fails, the deterministic rules output stands (PRD §8, AC8).
    private func applyCleanupLLM(to text: String, preferences: Preferences) async -> String {
        guard preferences.cleanupLLMEnabled else {
            environment.logger?.log(.cleanupSkipped(reason: .disabled))
            return text
        }
        guard let engine = await environment.cleanupEngine(), await engine.isAvailable() else {
            environment.logger?.log(.cleanupSkipped(reason: .noModelInstalled))
            return text
        }
        let started = Date()
        do {
            let cleaned = try await engine.clean(text, language: preferences.language)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            environment.logger?.log(.cleanupFinished(
                engine: engine.identifier,
                durationSeconds: Date().timeIntervalSince(started)
            ))
            // An empty or absent result must never lose the user's words.
            return cleaned.isEmpty ? text : cleaned
        } catch {
            environment.logger?.log(.cleanupSkipped(reason: .noModelInstalled))
            return text
        }
    }

    private func insert(_ text: String, preferences: Preferences) async {
        guard let method = await environment.insertion.insert(text) else {
            fail(.insertionFailed)
            return
        }
        environment.logger?.log(.inserted(method: method))

        if method == .clipboard {
            setHUD(.toast(Self.clipboardToastMessage))
            scheduleClipboardRestore(after: preferences.clipboardRetentionSeconds)
            hideHUD(after: preferences.errorDisplaySeconds)
        } else {
            setHUD(.done)
            hideHUD(after: preferences.completionDisplaySeconds)
        }
        setState(.idle)
    }

    private func scheduleClipboardRestore(after seconds: Double) {
        let clipboard = environment.clipboard
        let logger = environment.logger
        environment.scheduler.schedule(after: seconds) {
            let restored = clipboard.restoreIfUnchanged()
            logger?.log(.clipboardRestored(restored: restored))
        }
    }

    // MARK: - HUD and state plumbing

    private func fail(_ error: WaveError) {
        environment.logger?.log(.failed(error))
        setHUD(.error(error))
        setState(.idle)
        hideHUD(after: environment.preferences().errorDisplaySeconds)
    }

    private func hideHUD(after seconds: Double) {
        let generation = hudGeneration
        environment.scheduler.schedule(after: seconds) { [weak self] in
            await self?.hideHUDIfCurrent(generation: generation)
        }
    }

    private func hideHUDIfCurrent(generation: Int) {
        guard generation == hudGeneration, state == .idle else { return }
        setHUD(.hidden)
    }

    private func setState(_ newState: DictationState) {
        state = newState
        onStateChange?(newState)
    }

    private func setHUD(_ newHUD: HUDState) {
        hudGeneration += 1
        hud = newHUD
        onHUDChange?(newHUD)
    }
}
