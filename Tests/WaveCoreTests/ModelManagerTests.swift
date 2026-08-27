import Foundation
import Testing
@testable import WaveCore

private func makeTemporaryDirectory() -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("wave-models-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

/// Writes the descriptor's required files, unless told to fail or to produce a
/// partial (corrupt) download.
private final class FakeDownloader: ModelDownloader, @unchecked Sendable {
    enum Behaviour: Sendable {
        case succeed
        /// Fails this many times, then succeeds.
        case failTimes(Int)
        case alwaysFail
        /// Downloads, but omits the required files.
        case incomplete
    }

    private let behaviour: Behaviour
    private let attemptCount = Locked(0)

    init(_ behaviour: Behaviour) { self.behaviour = behaviour }

    var attempts: Int { attemptCount.current }

    func download(
        _ descriptor: ModelDescriptor,
        to destination: URL,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws {
        let currentAttempt = attemptCount.withValue { count -> Int in
            count += 1
            return count
        }

        progress(0.5)
        switch behaviour {
        case .alwaysFail:
            throw ModelError.downloadFailed
        case let .failTimes(count) where currentAttempt <= count:
            throw ModelError.downloadFailed
        case .incomplete:
            try Data("junk".utf8).write(to: destination.appendingPathComponent("unrelated.bin"))
        default:
            for file in descriptor.requiredFiles {
                try Data(descriptor.id.utf8).write(to: destination.appendingPathComponent(file))
            }
        }
        progress(1)
    }
}

private func descriptor(_ id: String, kind: ModelKind = .speech) -> ModelDescriptor {
    ModelDescriptor(
        id: id,
        kind: kind,
        displayName: id,
        repository: "argmaxinc/whisperkit-coreml",
        approximateBytes: 1_000,
        languages: ["pt-PT"],
        requiredFiles: ["model.bin", "config.json"]
    )
}

@Suite("ModelManager")
struct ModelManagerTests {
    @Test("installs a model and reports it as installed")
    func installsModel() async throws {
        let root = makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let manager = ModelManager(root: root, downloader: FakeDownloader(.succeed))

        let url = try await manager.install(descriptor("whisper-large-v3"))
        #expect(FileManager.default.fileExists(atPath: url.appendingPathComponent("model.bin").path))
        #expect(await manager.installedModel(kind: .speech)?.id == "whisper-large-v3")
    }

    @Test("stores models outside the app bundle, under Wave/Models")
    func usesApplicationSupport() {
        let root = ModelManager.defaultRoot()
        #expect(root.path.hasSuffix("Application Support/Wave/Models"))
    }

    @Test("replacing a model removes the old one only after the new one validates")
    func replacesModelInSafeOrder() async throws {
        let root = makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let manager = ModelManager(root: root, downloader: FakeDownloader(.succeed))

        let old = descriptor("whisper-small")
        let oldURL = try await manager.install(old)
        let newURL = try await manager.install(descriptor("whisper-large-v3"))

        #expect(FileManager.default.fileExists(atPath: newURL.appendingPathComponent("model.bin").path))
        #expect(FileManager.default.fileExists(atPath: oldURL.path) == false)
        #expect(await manager.installedModel(kind: .speech)?.id == "whisper-large-v3")
    }

    @Test("a failed replacement leaves the existing model working (AC9)")
    func failedReplacementKeepsOldModel() async throws {
        let root = makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let downloader = FakeDownloader(.succeed)
        let manager = ModelManager(root: root, downloader: downloader)
        let old = descriptor("whisper-small")
        let oldURL = try await manager.install(old)

        let failing = ModelManager(root: root, downloader: FakeDownloader(.alwaysFail))
        await #expect(throws: (any Error).self) {
            try await failing.install(descriptor("whisper-large-v3"))
        }

        #expect(FileManager.default.fileExists(atPath: oldURL.appendingPathComponent("model.bin").path))
        #expect(await failing.installedModel(kind: .speech)?.id == "whisper-small")
    }

    @Test("a corrupt download fails validation and is not activated")
    func corruptDownloadIsRejected() async throws {
        let root = makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let manager = ModelManager(root: root, downloader: FakeDownloader(.incomplete))

        await #expect(throws: (any Error).self) {
            try await manager.install(descriptor("whisper-large-v3"))
        }
        #expect(await manager.installedModel(kind: .speech) == nil)
    }

    @Test("retries the download once automatically, then succeeds")
    func retriesOnceAutomatically() async throws {
        let root = makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let downloader = FakeDownloader(.failTimes(1))
        let manager = ModelManager(root: root, downloader: downloader)

        _ = try await manager.install(descriptor("whisper-large-v3"))
        #expect(downloader.attempts == 2)
    }

    @Test("does not retry forever — two attempts then manual retry")
    func stopsAfterOneAutomaticRetry() async throws {
        let root = makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let downloader = FakeDownloader(.alwaysFail)
        let manager = ModelManager(root: root, downloader: downloader)

        let phases = PhaseRecorder()
        await #expect(throws: (any Error).self) {
            try await manager.install(descriptor("whisper-large-v3")) { phases.record($0) }
        }
        #expect(downloader.attempts == 2)
        #expect(phases.recorded.contains(.retrying))
        #expect(phases.recorded.contains(.failed(needsManualRetry: true)))
    }

    @Test("reports the install phases in order")
    func reportsPhases() async throws {
        let root = makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let manager = ModelManager(root: root, downloader: FakeDownloader(.succeed))
        let phases = PhaseRecorder()

        _ = try await manager.install(descriptor("whisper-large-v3")) { phases.record($0) }
        let recorded = phases.recorded
        #expect(recorded.contains(.validating))
        #expect(recorded.contains(.activating))
        #expect(recorded.last == .finished)
    }

    @Test("speech and cleanup models coexist independently")
    func kindsAreIndependent() async throws {
        let root = makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let manager = ModelManager(root: root, downloader: FakeDownloader(.succeed))

        _ = try await manager.install(descriptor("whisper-large-v3"))
        _ = try await manager.install(descriptor("qwen2.5-3b", kind: .cleanup))

        #expect(await manager.installedModel(kind: .speech)?.id == "whisper-large-v3")
        #expect(await manager.installedModel(kind: .cleanup)?.id == "qwen2.5-3b")
    }

    @Test("uninstalling the cleanup model is a supported state")
    func uninstallCleanupModel() async throws {
        let root = makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let manager = ModelManager(root: root, downloader: FakeDownloader(.succeed))

        _ = try await manager.install(descriptor("qwen2.5-3b", kind: .cleanup))
        await manager.uninstall(kind: .cleanup)
        #expect(await manager.installedModel(kind: .cleanup) == nil)
    }

    @Test("installed models survive a restart")
    func statePersists() async throws {
        let root = makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let manager = ModelManager(root: root, downloader: FakeDownloader(.succeed))
        _ = try await manager.install(descriptor("whisper-large-v3"))

        let reopened = ModelManager(root: root, downloader: FakeDownloader(.succeed))
        #expect(await reopened.installedModel(kind: .speech)?.id == "whisper-large-v3")
        #expect(await reopened.activeLocation(kind: .speech) != nil)
    }

    @Test("reinstalling the active model is a no-op")
    func reinstallIsNoOp() async throws {
        let root = makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let downloader = FakeDownloader(.succeed)
        let manager = ModelManager(root: root, downloader: downloader)

        _ = try await manager.install(descriptor("whisper-large-v3"))
        _ = try await manager.install(descriptor("whisper-large-v3"))
        #expect(downloader.attempts == 1)
    }
}

private final class PhaseRecorder: @unchecked Sendable {
    private let phases = Locked([ModelInstallPhase]())
    func record(_ phase: ModelInstallPhase) { phases.withValue { $0.append(phase) } }
    var recorded: [ModelInstallPhase] { phases.current }
}
