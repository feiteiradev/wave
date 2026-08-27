import Foundation
import WaveCore

/// Hands the dictation controller the engines for whatever models are
/// currently installed, rebuilding them when the user swaps a model (PRD §39).
public actor EngineProvider {
    private let modelManager: ModelManager
    private let logger: DiagnosticsLogger?
    private let idleUnloadSeconds: @Sendable () -> Double

    private var speechEngine: WhisperKitSTTEngine?
    private var speechModelID: String?
    private var cleanupEngine: MLXCleanupEngine?
    private var cleanupModelID: String?

    public init(
        modelManager: ModelManager,
        logger: DiagnosticsLogger? = nil,
        idleUnloadSeconds: @escaping @Sendable () -> Double = { 180 }
    ) {
        self.modelManager = modelManager
        self.logger = logger
        self.idleUnloadSeconds = idleUnloadSeconds
    }

    /// Nil when no speech model is installed — the controller then shows
    /// `Model unavailable` rather than failing silently (PRD §29).
    public func currentSpeechEngine() async -> (any STTEngine)? {
        guard let descriptor = await modelManager.installedModel(kind: .speech),
              let folder = await modelManager.activeLocation(kind: .speech)
        else { return nil }

        if let speechEngine, speechModelID == descriptor.id { return speechEngine }
        let engine = WhisperKitSTTEngine(modelFolder: folder, variant: descriptor.id)
        speechEngine = engine
        speechModelID = descriptor.id
        return engine
    }

    /// Nil when no cleanup model is installed. Clean still works — it just
    /// stops after the deterministic rules (PRD §8, AC8).
    public func currentCleanupEngine() async -> (any CleanupEngine)? {
        guard let descriptor = await modelManager.installedModel(kind: .cleanup),
              let folder = await modelManager.activeLocation(kind: .cleanup)
        else { return nil }

        if let cleanupEngine, cleanupModelID == descriptor.id { return cleanupEngine }
        await cleanupEngine?.unload()
        let engine = MLXCleanupEngine(
            modelDirectory: folder,
            modelID: descriptor.id,
            idleUnloadSeconds: idleUnloadSeconds(),
            logger: logger
        )
        cleanupEngine = engine
        cleanupModelID = descriptor.id
        return engine
    }

    /// Drops cached engines so the next dictation picks up a swapped model.
    public func invalidate(kind: ModelKind) async {
        switch kind {
        case .speech:
            speechEngine = nil
            speechModelID = nil
        case .cleanup:
            await cleanupEngine?.unload()
            cleanupEngine = nil
            cleanupModelID = nil
        }
    }
}
