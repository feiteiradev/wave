import Testing
@testable import WaveCore

private struct StubStrategy: TextInsertionStrategy {
    let method: InsertionMethod
    let result: Result<Bool, any Error>
    let recorder: Recorder

    func insert(_ text: String) async throws -> Bool {
        recorder.record(method)
        return try result.get()
    }
}

private final class Recorder: @unchecked Sendable {
    private let methods = Locked([InsertionMethod]())
    func record(_ method: InsertionMethod) { methods.withValue { $0.append(method) } }
    var attempted: [InsertionMethod] { methods.current }
}

import Foundation

@Suite("InsertionPipeline")
struct InsertionPipelineTests {
    @Test("uses Accessibility when it succeeds and stops there")
    func prefersAccessibility() async {
        let recorder = Recorder()
        let pipeline = InsertionPipeline(strategies: [
            StubStrategy(method: .accessibility, result: .success(true), recorder: recorder),
            StubStrategy(method: .simulatedPaste, result: .success(true), recorder: recorder),
        ])
        #expect(await pipeline.insert("olá") == .accessibility)
        #expect(recorder.attempted == [.accessibility])
    }

    @Test("falls through to simulated paste when Accessibility declines")
    func fallsThroughToPaste() async {
        let recorder = Recorder()
        let pipeline = InsertionPipeline(strategies: [
            StubStrategy(method: .accessibility, result: .success(false), recorder: recorder),
            StubStrategy(method: .simulatedPaste, result: .success(true), recorder: recorder),
        ])
        #expect(await pipeline.insert("olá") == .simulatedPaste)
        #expect(recorder.attempted == [.accessibility, .simulatedPaste])
    }

    @Test("a throwing strategy does not abort the chain")
    func throwingStrategyIsSkipped() async {
        struct Boom: Error {}
        let recorder = Recorder()
        let pipeline = InsertionPipeline(strategies: [
            StubStrategy(method: .accessibility, result: .failure(Boom()), recorder: recorder),
            StubStrategy(method: .simulatedPaste, result: .success(true), recorder: recorder),
        ])
        #expect(await pipeline.insert("olá") == .simulatedPaste)
    }

    @Test("reaches the clipboard when both direct methods fail")
    func reachesClipboard() async {
        let recorder = Recorder()
        let pipeline = InsertionPipeline(strategies: [
            StubStrategy(method: .accessibility, result: .success(false), recorder: recorder),
            StubStrategy(method: .simulatedPaste, result: .success(false), recorder: recorder),
            StubStrategy(method: .clipboard, result: .success(true), recorder: recorder),
        ])
        #expect(await pipeline.insert("olá") == .clipboard)
        #expect(recorder.attempted == [.accessibility, .simulatedPaste, .clipboard])
    }

    @Test("empty text is never inserted anywhere")
    func emptyTextIsNoOp() async {
        let recorder = Recorder()
        let pipeline = InsertionPipeline(strategies: [
            StubStrategy(method: .accessibility, result: .success(true), recorder: recorder),
        ])
        #expect(await pipeline.insert("") == nil)
        #expect(recorder.attempted.isEmpty)
    }
}

@Suite("ClipboardGuard")
struct ClipboardGuardTests {
    @Test("places the transcription on the clipboard")
    func placesText() {
        let clipboard = FakeClipboard("anterior")
        ClipboardGuard(clipboard: clipboard).place("transcrição")
        #expect(clipboard.stringContents == "transcrição")
    }

    @Test("restores the previous contents when untouched")
    func restoresWhenUntouched() {
        let clipboard = FakeClipboard("anterior")
        let guardian = ClipboardGuard(clipboard: clipboard)
        guardian.place("transcrição")
        #expect(guardian.restoreIfUnchanged())
        #expect(clipboard.stringContents == "anterior")
    }

    @Test("does not overwrite something the user copied meanwhile")
    func doesNotClobberUserCopy() {
        let clipboard = FakeClipboard("anterior")
        let guardian = ClipboardGuard(clipboard: clipboard)
        guardian.place("transcrição")
        clipboard.setStringContents("o utilizador copiou isto")
        #expect(guardian.restoreIfUnchanged() == false)
        #expect(clipboard.stringContents == "o utilizador copiou isto")
    }

    @Test("clears the clipboard when there was nothing to restore")
    func clearsWhenNoPrevious() {
        let clipboard = FakeClipboard(nil)
        let guardian = ClipboardGuard(clipboard: clipboard)
        guardian.place("transcrição")
        #expect(guardian.restoreIfUnchanged())
        #expect(clipboard.stringContents == nil)
    }

    @Test("a second dictation still restores the user's original clipboard")
    func keepsOriginalAcrossTwoDictations() {
        let clipboard = FakeClipboard("anterior")
        let guardian = ClipboardGuard(clipboard: clipboard)
        guardian.place("primeira")
        guardian.place("segunda")
        #expect(guardian.restoreIfUnchanged())
        #expect(clipboard.stringContents == "anterior")
    }

    @Test("restoring twice is harmless")
    func restoreIsIdempotent() {
        let clipboard = FakeClipboard("anterior")
        let guardian = ClipboardGuard(clipboard: clipboard)
        guardian.place("transcrição")
        #expect(guardian.restoreIfUnchanged())
        clipboard.setStringContents("outra coisa")
        #expect(guardian.restoreIfUnchanged() == false)
        #expect(clipboard.stringContents == "outra coisa")
    }

    @Test("reports whether a restore is pending")
    func reportsPendingRestore() {
        let guardian = ClipboardGuard(clipboard: FakeClipboard("anterior"))
        #expect(guardian.isHoldingClipboard == false)
        guardian.place("transcrição")
        #expect(guardian.isHoldingClipboard)
        guardian.restoreIfUnchanged()
        #expect(guardian.isHoldingClipboard == false)
    }
}
