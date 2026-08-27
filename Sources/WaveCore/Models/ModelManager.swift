import Foundation

/// Downloads, validates, activates and removes models (PRD §32–§35).
///
/// The install order is the load-bearing part (PRD §9.2, AC9): the model
/// currently in use is only deleted once its replacement has downloaded *and*
/// validated. A failed or corrupt download therefore leaves Wave exactly as it
/// was, still working.
///
/// Only one model of each kind is installed at a time (PRD §34, §44).
public actor ModelManager {
    /// One automatic retry, then the user must press Retry (PRD §35).
    public static let automaticRetries = 1

    private let root: URL
    private let downloader: any ModelDownloader
    private let fileManager = FileManager.default
    private let logger: DiagnosticsLogger?
    private var state: InstalledState

    public init(root: URL, downloader: any ModelDownloader, logger: DiagnosticsLogger? = nil) {
        self.root = root
        self.downloader = downloader
        self.logger = logger
        self.state = InstalledState.load(from: Self.stateURL(root: root)) ?? InstalledState()
    }

    /// `~/Library/Application Support/Wave/Models` (PRD §33).
    public static func defaultRoot() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Wave/Models", isDirectory: true)
    }

    public func installedModel(kind: ModelKind) -> ModelDescriptor? {
        state.installed[kind]
    }

    public func location(of descriptor: ModelDescriptor) -> URL {
        root
            .appendingPathComponent(descriptor.kind.directoryName, isDirectory: true)
            .appendingPathComponent(descriptor.id, isDirectory: true)
    }

    /// URL of the active model of a kind, if one is installed and present.
    public func activeLocation(kind: ModelKind) -> URL? {
        guard let descriptor = state.installed[kind] else { return nil }
        let url = location(of: descriptor)
        return fileManager.fileExists(atPath: url.path) ? url : nil
    }

    /// Downloads → validates → activates → removes the previous model.
    ///
    /// Retries the download once automatically. If it still fails, the previous
    /// model is untouched and the caller is told a manual retry is needed.
    @discardableResult
    public func install(
        _ descriptor: ModelDescriptor,
        onPhase: @escaping @Sendable (ModelInstallPhase) -> Void = { _ in }
    ) async throws -> URL {
        let previous = state.installed[descriptor.kind]
        if previous?.id == descriptor.id, let existing = activeLocation(kind: descriptor.kind) {
            onPhase(.finished)
            return existing
        }

        let staging = root
            .appendingPathComponent(".staging", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? fileManager.removeItem(at: staging) }

        logger?.log(.modelDownloadStarted(id: descriptor.id))

        var attempt = 0
        while true {
            do {
                try? fileManager.removeItem(at: staging)
                try fileManager.createDirectory(at: staging, withIntermediateDirectories: true)
                try await downloader.download(descriptor, to: staging) { fraction in
                    onPhase(.downloading(fraction: fraction))
                }
                onPhase(.validating)
                try validate(descriptor, at: staging)
                break
            } catch {
                let willRetry = attempt < Self.automaticRetries
                logger?.log(.modelDownloadFailed(id: descriptor.id, willRetry: willRetry))
                guard willRetry else {
                    onPhase(.failed(needsManualRetry: true))
                    // The previous model is still installed and untouched.
                    throw error
                }
                attempt += 1
                onPhase(.retrying)
            }
        }

        // Only now is it safe to touch what is already installed.
        onPhase(.activating)
        let destination = location(of: descriptor)
        try fileManager.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? fileManager.removeItem(at: destination)
        try fileManager.moveItem(at: staging, to: destination)

        state.installed[descriptor.kind] = descriptor
        try? state.save(to: Self.stateURL(root: root))
        logger?.log(.modelDownloadFinished(id: descriptor.id, bytes: descriptor.approximateBytes))

        if let previous, previous.id != descriptor.id {
            onPhase(.removingPrevious)
            try? fileManager.removeItem(at: location(of: previous))
        }

        onPhase(.finished)
        return destination
    }

    /// Removes the installed model of a kind. Used by the Cleanup section,
    /// where having no model at all is a valid configuration (PRD §8).
    public func uninstall(kind: ModelKind) {
        guard let descriptor = state.installed[kind] else { return }
        try? fileManager.removeItem(at: location(of: descriptor))
        state.installed[kind] = nil
        try? state.save(to: Self.stateURL(root: root))
        logger?.log(.modelUnloaded(id: descriptor.id))
    }

    private func validate(_ descriptor: ModelDescriptor, at url: URL) throws {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw ModelError.validationFailed(missingFile: nil)
        }
        for file in descriptor.requiredFiles {
            let candidate = url.appendingPathComponent(file)
            guard fileManager.fileExists(atPath: candidate.path) else {
                throw ModelError.validationFailed(missingFile: file)
            }
        }
        let contents = (try? fileManager.contentsOfDirectory(atPath: url.path)) ?? []
        guard !contents.isEmpty else { throw ModelError.validationFailed(missingFile: nil) }
    }

    private static func stateURL(root: URL) -> URL {
        root.appendingPathComponent("installed.json")
    }

    private struct InstalledState: Codable {
        var installed: [ModelKind: ModelDescriptor] = [:]

        static func load(from url: URL) -> InstalledState? {
            guard let data = try? Data(contentsOf: url) else { return nil }
            return try? JSONDecoder().decode(InstalledState.self, from: data)
        }

        func save(to url: URL) throws {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try JSONEncoder().encode(self).write(to: url, options: .atomic)
        }
    }
}
