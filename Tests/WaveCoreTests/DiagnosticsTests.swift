import Foundation
import Testing
@testable import WaveCore

private func makeTemporaryDirectory() -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("wave-tests-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private final class MutableClock: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Date
    init(_ value: Date) { self.value = value }
    var now: Date {
        get { lock.lock(); defer { lock.unlock() }; return value }
        set { lock.lock(); defer { lock.unlock() }; value = newValue }
    }
}

@Suite("DiagnosticsLogger")
struct DiagnosticsLoggerTests {
    @Test("writes an event to today's log file")
    func writesEvent() throws {
        let directory = makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let logger = DiagnosticsLogger(directory: directory)
        logger.log(.inserted(method: .accessibility))

        let contents = try String(contentsOf: logger.currentLogFileURL(), encoding: .utf8)
        #expect(contents.contains("Insertion: accessibility"))
    }

    @Test("appends rather than overwriting")
    func appendsEvents() throws {
        let directory = makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let logger = DiagnosticsLogger(directory: directory)
        logger.log(.recordingStarted(microphone: "System Default", mode: .clean))
        logger.log(.recordingFinished(durationSeconds: 12.4))

        let contents = try String(contentsOf: logger.currentLogFileURL(), encoding: .utf8)
        #expect(contents.contains("Recording started"))
        #expect(contents.contains("Recording duration: 12.4s"))
        #expect(contents.split(separator: "\n").count == 2)
    }

    @Test("deletes log files older than the age limit")
    func enforcesAgeLimit() {
        let directory = makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let clock = MutableClock(Date(timeIntervalSince1970: 1_700_000_000))
        let logger = DiagnosticsLogger(
            directory: directory,
            retention: .init(maximumAge: 7 * 24 * 3600, maximumTotalBytes: 10 * 1_024 * 1_024),
            now: { clock.now }
        )
        logger.log(.noSpeechDetected)
        let oldFile = logger.currentLogFileURL()

        clock.now = clock.now.addingTimeInterval(8 * 24 * 3600)
        logger.log(.noSpeechDetected)

        #expect(FileManager.default.fileExists(atPath: oldFile.path) == false)
        #expect(FileManager.default.fileExists(atPath: logger.currentLogFileURL().path))
    }

    @Test("keeps files that are still inside the age limit")
    func keepsRecentFiles() {
        let directory = makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let clock = MutableClock(Date(timeIntervalSince1970: 1_700_000_000))
        let logger = DiagnosticsLogger(directory: directory, now: { clock.now })
        logger.log(.noSpeechDetected)
        let recentFile = logger.currentLogFileURL()

        clock.now = clock.now.addingTimeInterval(3 * 24 * 3600)
        logger.log(.noSpeechDetected)

        #expect(FileManager.default.fileExists(atPath: recentFile.path))
        #expect(logger.logFileURLs().count == 2)
    }

    @Test("drops the oldest files once the size limit is exceeded")
    func enforcesSizeLimit() {
        let directory = makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let clock = MutableClock(Date(timeIntervalSince1970: 1_700_000_000))
        let logger = DiagnosticsLogger(
            directory: directory,
            retention: .init(maximumAge: 365 * 24 * 3600, maximumTotalBytes: 200),
            now: { clock.now }
        )
        for day in 0..<5 {
            clock.now = Date(timeIntervalSince1970: 1_700_000_000 + Double(day) * 24 * 3600)
            for _ in 0..<4 { logger.log(.recordingFinished(durationSeconds: 12.4)) }
        }

        let total = logger.logFileURLs().reduce(Int64(0)) { sum, url in
            sum + Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
        #expect(total <= 200)
        #expect(logger.logFileURLs().isEmpty == false)
    }

    @Test("no event can carry transcribed text into a log line")
    func neverLogsContent() {
        // The event type is a closed enum of metadata-only cases, so this is a
        // guard against someone adding a free-form case later (PRD §37.1).
        let secret = "Isto é o que o utilizador disse em voz alta"
        let events: [DiagnosticEvent] = [
            .recordingStarted(microphone: "System Default", mode: .clean),
            .recordingFinished(durationSeconds: 12.4),
            .noSpeechDetected,
            .transcriptionStarted(model: "whisper-large-v3", chunks: 3),
            .transcriptionFinished(durationSeconds: 1.8, characterCount: secret.count),
            .cleanupSkipped(reason: .noModelInstalled),
            .cleanupFinished(engine: "qwen2.5-3b", durationSeconds: 0.7),
            .inserted(method: .clipboard),
            .clipboardRestored(restored: true),
            .activationIgnored,
            .failed(.transcriptionFailed),
        ]
        for event in events {
            #expect(event.message.contains(secret) == false)
            #expect(event.message.contains("utilizador disse") == false)
        }
    }
}
