import Foundation
@testable import WaveCore

final class FakeRecorder: AudioRecording, @unchecked Sendable {
    private struct State {
        var startCount = 0
        var stopCount = 0
        var cancelCount = 0
        var requestedMicrophone: String??
    }

    private let buffer: AudioBuffer
    private let startError: (any Error)?
    private let state = Locked(State())

    init(buffer: AudioBuffer, startError: (any Error)? = nil) {
        self.buffer = buffer
        self.startError = startError
    }

    func start(microphoneUniqueID: String?, onLevel: @escaping @Sendable (Float) -> Void) async throws {
        state.withValue {
            $0.startCount += 1
            $0.requestedMicrophone = microphoneUniqueID
        }
        if let startError { throw startError }
        onLevel(0.42)
    }

    func stop() async -> AudioBuffer {
        state.withValue { $0.stopCount += 1 }
        return buffer
    }

    func cancel() async {
        state.withValue { $0.cancelCount += 1 }
    }

    var startCount: Int { state.current.startCount }
    var stopCount: Int { state.current.stopCount }
    var cancelCount: Int { state.current.cancelCount }
    var requestedMicrophone: String?? { state.current.requestedMicrophone }
}

final class FakeSTTEngine: STTEngine, @unchecked Sendable {
    let identifier = "fake-stt"

    private struct State {
        var receivedChunks = 0
        var receivedHotwords: [String] = []
        var receivedLanguage: String?
    }

    private let results: [String]
    private let error: (any Error)?
    private let state = Locked(State())

    init(results: [String], error: (any Error)? = nil) {
        self.results = results
        self.error = error
    }

    convenience init(result: String) { self.init(results: [result]) }

    func prepare() async throws {}

    func transcribe(_ buffer: AudioBuffer, language: String, hotwords: [String]) async throws -> String {
        if let error { throw error }
        return state.withValue {
            $0.receivedLanguage = language
            $0.receivedHotwords = hotwords
            let index = $0.receivedChunks
            $0.receivedChunks += 1
            return index < results.count ? results[index] : ""
        }
    }

    var receivedChunks: Int { state.current.receivedChunks }
    var receivedHotwords: [String] { state.current.receivedHotwords }
    var receivedLanguage: String? { state.current.receivedLanguage }
}

final class FakeCleanupEngine: CleanupEngine, @unchecked Sendable {
    let identifier = "fake-llm"

    private let available: Bool
    private let transform: @Sendable (String) throws -> String
    private let counts = Locked((clean: 0, unload: 0))

    init(available: Bool = true, transform: @escaping @Sendable (String) throws -> String = { $0.uppercased() }) {
        self.available = available
        self.transform = transform
    }

    func isAvailable() async -> Bool { available }

    func clean(_ text: String, language: String) async throws -> String {
        counts.withValue { $0.clean += 1 }
        return try transform(text)
    }

    func unload() async {
        counts.withValue { $0.unload += 1 }
    }

    var cleanCount: Int { counts.current.clean }
    var unloadCount: Int { counts.current.unload }
}

final class RecordingStrategy: TextInsertionStrategy, @unchecked Sendable {
    let method: InsertionMethod
    private let succeeds: Bool
    private let texts = Locked([String]())

    init(method: InsertionMethod, succeeds: Bool) {
        self.method = method
        self.succeeds = succeeds
    }

    func insert(_ text: String) async throws -> Bool {
        texts.withValue { $0.append(text) }
        return succeeds
    }

    var inserted: [String] { texts.current }
}

final class FakePasteboard: Pasteboard, @unchecked Sendable {
    private let value: Locked<String?>

    init(_ value: String? = nil) { self.value = Locked(value) }

    var stringContents: String? { value.current }

    func setStringContents(_ newValue: String?) {
        value.withValue { $0 = newValue }
    }
}

/// Runs scheduled work immediately, so HUD auto-hide and clipboard restore are
/// observable without waiting.
struct ImmediateScheduler: Scheduler {
    func schedule(after seconds: Double, _ work: @escaping @Sendable () async -> Void) {
        Task { await work() }
    }
}

/// Never runs scheduled work, so a test can inspect state before auto-hide.
struct NeverScheduler: Scheduler {
    func schedule(after seconds: Double, _ work: @escaping @Sendable () async -> Void) {}
}

final class StateRecorder: @unchecked Sendable {
    private let states = Locked([DictationState]())
    private let huds = Locked([HUDState]())

    func recordState(_ state: DictationState) { states.withValue { $0.append(state) } }
    func recordHUD(_ hud: HUDState) { huds.withValue { $0.append(hud) } }

    var recordedStates: [DictationState] { states.current }
    var recordedHUDs: [HUDState] { huds.current }
}

func speechBuffer(seconds: Double = 2, sampleRate: Double = 16_000) -> AudioBuffer {
    let count = Int(seconds * sampleRate)
    let samples = (0..<count).map { index in
        0.4 * sin(Float(index) * 2 * .pi * 220 / Float(sampleRate))
    }
    return AudioBuffer(samples: samples, sampleRate: sampleRate)
}

func silentBuffer(seconds: Double = 2, sampleRate: Double = 16_000) -> AudioBuffer {
    AudioBuffer(samples: [Float](repeating: 0, count: Int(seconds * sampleRate)), sampleRate: sampleRate)
}
