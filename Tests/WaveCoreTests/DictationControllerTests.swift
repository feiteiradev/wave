import Foundation
import Testing
@testable import WaveCore

private struct Harness {
    let controller: DictationController
    let recorder: FakeRecorder
    let stt: FakeSTTEngine
    let cleanup: FakeCleanupEngine?
    let accessibility: RecordingStrategy
    let paste: RecordingStrategy
    let pasteboard: FakePasteboard
    let clipboard: ClipboardGuard
    let observer: StateRecorder

    @discardableResult
    func settle() async -> DictationState {
        await controller.currentState
    }
}

private func makeHarness(
    buffer: AudioBuffer = speechBuffer(),
    transcripts: [String] = ["olá mundo"],
    sttError: (any Error)? = nil,
    recorderError: (any Error)? = nil,
    cleanup: FakeCleanupEngine? = FakeCleanupEngine(),
    accessibilitySucceeds: Bool = true,
    pasteSucceeds: Bool = true,
    preferences: Preferences = Preferences(),
    scheduler: any Scheduler = NeverScheduler(),
    chunker: AudioChunker = AudioChunker()
) -> Harness {
    let recorder = FakeRecorder(buffer: buffer, startError: recorderError)
    let stt = FakeSTTEngine(results: transcripts, error: sttError)
    let accessibility = RecordingStrategy(method: .accessibility, succeeds: accessibilitySucceeds)
    let paste = RecordingStrategy(method: .simulatedPaste, succeeds: pasteSucceeds)
    let pasteboard = FakePasteboard("clipboard anterior")
    let clipboard = ClipboardGuard(pasteboard: pasteboard)
    let observer = StateRecorder()

    let environment = DictationController.Environment(
        recorder: recorder,
        speechEngine: { stt },
        cleanupEngine: { cleanup },
        insertion: InsertionPipeline(strategies: [
            accessibility,
            paste,
            ClipboardInsertionStrategy(guardian: clipboard),
        ]),
        clipboard: clipboard,
        preferences: { preferences },
        logger: nil,
        scheduler: scheduler,
        chunker: chunker
    )

    return Harness(
        controller: DictationController(environment: environment),
        recorder: recorder,
        stt: stt,
        cleanup: cleanup,
        accessibility: accessibility,
        paste: paste,
        pasteboard: pasteboard,
        clipboard: clipboard,
        observer: observer
    )
}

@Suite("DictationController — basic dictation")
struct DictationControllerBasicTests {
    @Test("AC1: press, speak, release inserts cleaned text at the cursor")
    func cleanDictationInsertsText() async {
        let harness = makeHarness(transcripts: ["olá mundo"], cleanup: nil)
        await harness.controller.hotkeyPressed(mode: .clean)
        #expect(await harness.controller.currentState == .recording(mode: .clean))

        await harness.controller.hotkeyReleased(mode: .clean)
        #expect(harness.accessibility.inserted == ["Olá mundo"])
        #expect(await harness.controller.currentState == .idle)
        #expect(await harness.controller.currentHUD == .done)
    }

    @Test("AC2: Raw applies vocabulary but never the LLM")
    func rawSkipsCleanup() async {
        let cleanup = FakeCleanupEngine()
        var preferences = Preferences()
        preferences.vocabulary = [VocabularyTerm(term: "DearLift", aliases: ["dear lift"])]
        let harness = makeHarness(
            transcripts: ["vou usar o dear lift"],
            cleanup: cleanup,
            preferences: preferences
        )

        await harness.controller.hotkeyPressed(mode: .raw)
        await harness.controller.hotkeyReleased(mode: .raw)

        // Vocabulary applied; capitalization and other cleanup untouched.
        #expect(harness.accessibility.inserted == ["vou usar o DearLift"])
        #expect(cleanup.cleanCount == 0)
    }

    @Test("Clean runs the rules and then the LLM")
    func cleanRunsRulesThenLLM() async {
        let cleanup = FakeCleanupEngine { "LLM: " + $0 }
        let harness = makeHarness(transcripts: ["olá , tudo bem ?"], cleanup: cleanup)

        await harness.controller.hotkeyPressed(mode: .clean)
        await harness.controller.hotkeyReleased(mode: .clean)

        #expect(cleanup.cleanCount == 1)
        #expect(harness.accessibility.inserted == ["LLM: Olá, tudo bem?"])
    }

    @Test("AC8: Clean works with no LLM installed")
    func cleanWorksWithoutLLM() async {
        let harness = makeHarness(transcripts: ["olá . tudo bem"], cleanup: nil)
        await harness.controller.hotkeyPressed(mode: .clean)
        await harness.controller.hotkeyReleased(mode: .clean)
        #expect(harness.accessibility.inserted == ["Olá. Tudo bem"])
    }

    @Test("an unavailable LLM falls back to the rules output")
    func unavailableLLMFallsBack() async {
        let cleanup = FakeCleanupEngine(available: false)
        let harness = makeHarness(transcripts: ["olá mundo"], cleanup: cleanup)
        await harness.controller.hotkeyPressed(mode: .clean)
        await harness.controller.hotkeyReleased(mode: .clean)
        #expect(harness.accessibility.inserted == ["Olá mundo"])
        #expect(cleanup.cleanCount == 0)
    }

    @Test("a failing LLM never loses the transcription")
    func failingLLMKeepsText() async {
        struct Boom: Error {}
        let cleanup = FakeCleanupEngine { _ in throw Boom() }
        let harness = makeHarness(transcripts: ["olá mundo"], cleanup: cleanup)
        await harness.controller.hotkeyPressed(mode: .clean)
        await harness.controller.hotkeyReleased(mode: .clean)
        #expect(harness.accessibility.inserted == ["Olá mundo"])
    }

    @Test("an LLM returning nothing never loses the transcription")
    func emptyLLMOutputKeepsText() async {
        let cleanup = FakeCleanupEngine { _ in "   " }
        let harness = makeHarness(transcripts: ["olá mundo"], cleanup: cleanup)
        await harness.controller.hotkeyPressed(mode: .clean)
        await harness.controller.hotkeyReleased(mode: .clean)
        #expect(harness.accessibility.inserted == ["Olá mundo"])
    }

    @Test("the configured language and vocabulary hints reach the STT engine")
    func passesLanguageAndHotwords() async {
        var preferences = Preferences()
        preferences.language = "pt-PT"
        preferences.vocabulary = [VocabularyTerm(term: "DearLift", aliases: ["dear lift"])]
        let harness = makeHarness(preferences: preferences)

        await harness.controller.hotkeyPressed(mode: .clean)
        await harness.controller.hotkeyReleased(mode: .clean)

        #expect(harness.stt.receivedLanguage == "pt-PT")
        #expect(harness.stt.receivedHotwords == ["DearLift"])
    }

    @Test("the configured microphone is requested")
    func passesMicrophone() async {
        var preferences = Preferences()
        preferences.microphoneUniqueID = "AirPods"
        let harness = makeHarness(preferences: preferences)
        await harness.controller.hotkeyPressed(mode: .clean)
        #expect(harness.recorder.requestedMicrophone == "AirPods")
    }
}

@Suite("DictationController — no speech and errors")
struct DictationControllerFailureTests {
    @Test("AC7: no speech produces no text and no notification")
    func noSpeechCancelsSilently() async {
        let harness = makeHarness(buffer: silentBuffer())
        await harness.controller.hotkeyPressed(mode: .clean)
        await harness.controller.hotkeyReleased(mode: .clean)

        #expect(harness.accessibility.inserted.isEmpty)
        #expect(harness.pasteboard.stringContents == "clipboard anterior")
        #expect(await harness.controller.currentHUD == .hidden)
        #expect(await harness.controller.currentState == .idle)
    }

    @Test("an empty transcription is also a silent cancel")
    func emptyTranscriptionCancelsSilently() async {
        let harness = makeHarness(transcripts: ["   "], cleanup: nil)
        await harness.controller.hotkeyPressed(mode: .clean)
        await harness.controller.hotkeyReleased(mode: .clean)
        #expect(harness.accessibility.inserted.isEmpty)
        #expect(await harness.controller.currentHUD == .hidden)
    }

    @Test("an unavailable microphone shows the microphone error")
    func microphoneErrorShown() async {
        struct Boom: Error {}
        let harness = makeHarness(recorderError: Boom())
        await harness.controller.hotkeyPressed(mode: .clean)

        #expect(await harness.controller.currentHUD == .error(.microphoneUnavailable))
        #expect(await harness.controller.currentState == .idle)
        #expect(harness.recorder.cancelCount == 1)
    }

    @Test("a failing STT shows the transcription error")
    func transcriptionErrorShown() async {
        struct Boom: Error {}
        let harness = makeHarness(sttError: Boom())
        await harness.controller.hotkeyPressed(mode: .clean)
        await harness.controller.hotkeyReleased(mode: .clean)

        #expect(await harness.controller.currentHUD == .error(.transcriptionFailed))
        #expect(await harness.controller.currentState == .idle)
    }

    @Test("a missing STT model shows the model error")
    func missingModelErrorShown() async {
        let recorder = FakeRecorder(buffer: speechBuffer())
        let clipboard = ClipboardGuard(pasteboard: FakePasteboard())
        let environment = DictationController.Environment(
            recorder: recorder,
            speechEngine: { nil },
            cleanupEngine: { nil },
            insertion: InsertionPipeline(strategies: []),
            clipboard: clipboard,
            preferences: { Preferences() },
            scheduler: NeverScheduler()
        )
        let controller = DictationController(environment: environment)

        await controller.hotkeyPressed(mode: .clean)
        await controller.hotkeyReleased(mode: .clean)
        #expect(await controller.currentHUD == .error(.modelUnavailable))
    }

    @Test("errors auto-hide once the display period elapses")
    func errorsAutoHide() async {
        struct Boom: Error {}
        let harness = makeHarness(recorderError: Boom(), scheduler: ImmediateScheduler())
        await harness.controller.hotkeyPressed(mode: .clean)
        try? await Task.sleep(nanoseconds: 50_000_000)
        #expect(await harness.controller.currentHUD == .hidden)
    }
}

@Suite("DictationController — insertion fallback")
struct DictationControllerInsertionTests {
    @Test("AC3: falls back to the clipboard and shows the toast")
    func clipboardFallbackShowsToast() async {
        let harness = makeHarness(
            transcripts: ["olá mundo"],
            cleanup: nil,
            accessibilitySucceeds: false,
            pasteSucceeds: false
        )
        await harness.controller.hotkeyPressed(mode: .clean)
        await harness.controller.hotkeyReleased(mode: .clean)

        #expect(harness.pasteboard.stringContents == "Olá mundo")
        #expect(await harness.controller.currentHUD == .toast(DictationController.clipboardToastMessage))
    }

    @Test("AC3: the previous clipboard comes back after the retention period")
    func clipboardRestoredAfterRetention() async {
        let harness = makeHarness(
            transcripts: ["olá mundo"],
            cleanup: nil,
            accessibilitySucceeds: false,
            pasteSucceeds: false,
            scheduler: ImmediateScheduler()
        )
        await harness.controller.hotkeyPressed(mode: .clean)
        await harness.controller.hotkeyReleased(mode: .clean)
        try? await Task.sleep(nanoseconds: 50_000_000)

        #expect(harness.pasteboard.stringContents == "clipboard anterior")
    }

    @Test("a clipboard the user changed is left alone")
    func userClipboardNotClobbered() async {
        let harness = makeHarness(
            transcripts: ["olá mundo"],
            cleanup: nil,
            accessibilitySucceeds: false,
            pasteSucceeds: false,
            scheduler: NeverScheduler()
        )
        await harness.controller.hotkeyPressed(mode: .clean)
        await harness.controller.hotkeyReleased(mode: .clean)
        harness.pasteboard.setStringContents("o utilizador copiou outra coisa")
        #expect(harness.clipboard.restoreIfUnchanged() == false)
        #expect(harness.pasteboard.stringContents == "o utilizador copiou outra coisa")
    }

    @Test("simulated paste is used when Accessibility declines")
    func usesSimulatedPaste() async {
        let harness = makeHarness(
            transcripts: ["olá mundo"],
            cleanup: nil,
            accessibilitySucceeds: false,
            pasteSucceeds: true
        )
        await harness.controller.hotkeyPressed(mode: .clean)
        await harness.controller.hotkeyReleased(mode: .clean)
        #expect(harness.paste.inserted == ["Olá mundo"])
        #expect(await harness.controller.currentHUD == .done)
    }
}

@Suite("DictationController — activation modes and concurrency")
struct DictationControllerActivationTests {
    @Test("AC10: an activation during processing is ignored, HUD keeps processing")
    func secondActivationIgnored() async {
        // A slow STT keeps the controller in `processing` while a second
        // activation arrives.
        let gate = Locked(false)
        final class SlowSTT: STTEngine, @unchecked Sendable {
            let identifier = "slow"
            let gate: Locked<Bool>
            init(gate: Locked<Bool>) { self.gate = gate }
            func prepare() async throws {}
            func transcribe(_ buffer: AudioBuffer, language: String, hotwords: [String]) async throws -> String {
                while !gate.current { await Task.yield() }
                return "olá"
            }
        }

        let recorder = FakeRecorder(buffer: speechBuffer())
        let accessibility = RecordingStrategy(method: .accessibility, succeeds: true)
        let clipboard = ClipboardGuard(pasteboard: FakePasteboard())
        let environment = DictationController.Environment(
            recorder: recorder,
            speechEngine: { SlowSTT(gate: gate) },
            cleanupEngine: { nil },
            insertion: InsertionPipeline(strategies: [accessibility]),
            clipboard: clipboard,
            preferences: { Preferences() },
            scheduler: NeverScheduler()
        )
        let controller = DictationController(environment: environment)

        await controller.hotkeyPressed(mode: .clean)
        let processing = Task { await controller.hotkeyReleased(mode: .clean) }

        // Wait until it is genuinely in the processing state.
        while await controller.currentState != .processing(mode: .clean) { await Task.yield() }

        await controller.hotkeyPressed(mode: .raw)
        #expect(await controller.currentState == .processing(mode: .clean))
        #expect(await controller.currentHUD == .processing)
        #expect(recorder.startCount == 1)

        gate.withValue { $0 = true }
        await processing.value
        #expect(accessibility.inserted == ["Olá"])
    }

    @Test("push-to-talk: release stops the recording")
    func pushToTalkStopsOnRelease() async {
        var preferences = Preferences()
        preferences.activationMode = .pushToTalk
        let harness = makeHarness(cleanup: nil, preferences: preferences)

        await harness.controller.hotkeyPressed(mode: .clean)
        #expect(await harness.controller.currentState == .recording(mode: .clean))
        await harness.controller.hotkeyReleased(mode: .clean)
        #expect(harness.recorder.stopCount == 1)
    }

    @Test("toggle: release does nothing, a second press stops")
    func toggleStopsOnSecondPress() async {
        var preferences = Preferences()
        preferences.activationMode = .toggle
        let harness = makeHarness(cleanup: nil, preferences: preferences)

        await harness.controller.hotkeyPressed(mode: .clean)
        await harness.controller.hotkeyReleased(mode: .clean)
        #expect(await harness.controller.currentState == .recording(mode: .clean))
        #expect(harness.recorder.stopCount == 0)

        await harness.controller.hotkeyPressed(mode: .clean)
        #expect(harness.recorder.stopCount == 1)
        #expect(await harness.controller.currentState == .idle)
    }

    @Test("the activation mode is global across both hotkeys")
    func activationModeIsGlobal() async {
        var preferences = Preferences()
        preferences.activationMode = .toggle
        let harness = makeHarness(cleanup: nil, preferences: preferences)

        await harness.controller.hotkeyPressed(mode: .raw)
        await harness.controller.hotkeyReleased(mode: .raw)
        #expect(await harness.controller.currentState == .recording(mode: .raw))
        await harness.controller.hotkeyPressed(mode: .raw)
        #expect(await harness.controller.currentState == .idle)
    }

    @Test("§25: the menu bar item toggles even in push-to-talk mode")
    func menuBarBehavesAsToggle() async {
        var preferences = Preferences()
        preferences.activationMode = .pushToTalk
        let harness = makeHarness(cleanup: nil, preferences: preferences)

        await harness.controller.menuBarToggle()
        #expect(await harness.controller.currentState == .recording(mode: .clean))
        await harness.controller.menuBarToggle()
        #expect(harness.recorder.stopCount == 1)
        #expect(await harness.controller.currentState == .idle)
    }

    @Test("§25: the menu bar always starts a Clean dictation")
    func menuBarStartsClean() async {
        let cleanup = FakeCleanupEngine { "LLM: " + $0 }
        let harness = makeHarness(transcripts: ["olá"], cleanup: cleanup)
        await harness.controller.menuBarToggle()
        await harness.controller.menuBarToggle()
        #expect(cleanup.cleanCount == 1)
    }

    @Test("HUD reports recording level while capturing")
    func hudTracksLevel() async {
        let harness = makeHarness(cleanup: nil)
        await harness.controller.hotkeyPressed(mode: .clean)
        // Level callbacks arrive from the capture thread and hop onto the
        // actor, so the HUD catches up a moment later.
        while await harness.controller.currentHUD == .recording(level: 0) { await Task.yield() }
        #expect(await harness.controller.currentHUD == .recording(level: 0.42))
    }
}

@Suite("DictationController — long recordings")
struct DictationControllerChunkingTests {
    @Test("AC6: a long recording is chunked and recombined transparently")
    func longRecordingIsChunkedAndJoined() async {
        let harness = makeHarness(
            buffer: speechBuffer(seconds: 70),
            transcripts: ["primeira parte", "segunda parte", "terceira parte"],
            cleanup: nil,
            chunker: AudioChunker(targetSeconds: 25, maxSeconds: 30, searchWindowSeconds: 8)
        )

        await harness.controller.hotkeyPressed(mode: .clean)
        await harness.controller.hotkeyReleased(mode: .clean)

        #expect(harness.stt.receivedChunks == 3)
        #expect(harness.accessibility.inserted == ["Primeira parte segunda parte terceira parte"])
    }

    @Test("a short recording is a single STT call")
    func shortRecordingIsOneCall() async {
        let harness = makeHarness(buffer: speechBuffer(seconds: 3), cleanup: nil)
        await harness.controller.hotkeyPressed(mode: .clean)
        await harness.controller.hotkeyReleased(mode: .clean)
        #expect(harness.stt.receivedChunks == 1)
    }

    @Test("§17: a very short utterance is still transcribed")
    func shortUtteranceIsProcessed() async {
        let harness = makeHarness(
            buffer: speechBuffer(seconds: 0.4),
            transcripts: ["olá"],
            cleanup: nil
        )
        await harness.controller.hotkeyPressed(mode: .clean)
        await harness.controller.hotkeyReleased(mode: .clean)
        #expect(harness.accessibility.inserted == ["Olá"])
    }
}
