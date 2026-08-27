import AppKit
import Combine
import Foundation
import WaveCore
import WavePlatform

/// Wires the whole application together and exposes its state to SwiftUI.
///
/// This is the only place that knows about every piece: preferences, the model
/// manager, the engines, the hotkeys and the dictation controller. Everything
/// else observes it.
@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var dictationState: DictationState = .idle
    @Published private(set) var hud: HUDState = .hidden
    /// Rolling recent levels driving the HUD waveform (PRD §27).
    @Published private(set) var waveform: [Float] = []
    @Published private(set) var installedSpeechModel: ModelDescriptor?
    @Published private(set) var installedCleanupModel: ModelDescriptor?
    /// Keyed by model id, so a failed download marks only the model the user
    /// actually tried to install.
    @Published private(set) var installPhase: [String: ModelInstallPhase] = [:]
    @Published private(set) var microphones: [AudioInputDevice] = []
    @Published private(set) var permissions: [Permission: Bool] = [:]
    @Published private(set) var hotkeyConflicts: [DictationMode] = []
    @Published private(set) var statusMessage: String = "Ready"

    @Published var preferences: Preferences {
        didSet {
            guard preferences != oldValue else { return }
            preferencesStore.save(preferences)
            applyPreferences(previous: oldValue)
        }
    }

    static let waveformSampleCount = 48

    let logger: DiagnosticsLogger
    let modelManager: ModelManager

    private let preferencesStore: any PreferencesStore
    private let clipboard: ClipboardGuard
    private let engines: EngineProvider
    private let recorder: MicrophoneRecorder
    private var controller: DictationController!
    private var hotkeys: GlobalHotkeyMonitor!

    init(
        preferencesStore: any PreferencesStore = FilePreferencesStore(),
        logsDirectory: URL = AppModel.defaultLogsDirectory()
    ) {
        let preferences = preferencesStore.load()
        self.preferencesStore = preferencesStore
        self.preferences = preferences
        self.logger = DiagnosticsLogger(directory: logsDirectory)
        self.clipboard = ClipboardGuard(clipboard: MacSystemClipboard())

        let modelManager = ModelManager(
            root: ModelManager.defaultRoot(),
            downloader: KindRoutingDownloader(),
            logger: logger
        )
        self.modelManager = modelManager
        self.engines = EngineProvider(modelManager: modelManager, logger: logger)
        self.recorder = MicrophoneRecorder()

        let engines = self.engines
        let clipboard = self.clipboard
        let logger = self.logger
        // A weak read of preferences, so the controller always sees the
        // current settings without holding a stale copy.
        let readPreferences = PreferencesBox(preferences)
        self.preferencesBox = readPreferences

        let environment = DictationController.Environment(
            recorder: recorder,
            speechEngine: { await engines.currentSpeechEngine() },
            cleanupEngine: { await engines.currentCleanupEngine() },
            insertion: InsertionPipeline(strategies: [
                AccessibilityInserter(),
                SimulatedPasteInserter(guardian: clipboard),
                ClipboardInsertionStrategy(guardian: clipboard),
            ]),
            clipboard: clipboard,
            preferences: { readPreferences.value },
            logger: logger
        )
        self.controller = DictationController(environment: environment)

        self.hotkeys = GlobalHotkeyMonitor(
            onPressed: { [weak self] mode in
                Task { @MainActor in await self?.controller.hotkeyPressed(mode: mode) }
            },
            onReleased: { [weak self] mode in
                Task { @MainActor in await self?.controller.hotkeyReleased(mode: mode) }
            }
        )
    }

    private let preferencesBox: PreferencesBox

    nonisolated static func defaultLogsDirectory() -> URL {
        let base = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Logs/Wave", isDirectory: true)
    }

    // MARK: - Lifecycle

    func start() async {
        await controller.observe(
            state: { [weak self] state in
                Task { @MainActor in self?.handleStateChange(state) }
            },
            hud: { [weak self] hud in
                Task { @MainActor in self?.handleHUDChange(hud) }
            }
        )
        refreshMicrophones()
        refreshPermissions()
        await refreshInstalledModels()
        registerHotkeys()
        LoginItem.setEnabled(preferences.launchAtLogin)
    }

    private func applyPreferences(previous: Preferences) {
        preferencesBox.value = preferences
        if preferences.cleanHotkey != previous.cleanHotkey || preferences.rawHotkey != previous.rawHotkey {
            registerHotkeys()
        }
        if preferences.launchAtLogin != previous.launchAtLogin {
            LoginItem.setEnabled(preferences.launchAtLogin)
        }
    }

    private func registerHotkeys() {
        hotkeyConflicts = hotkeys.register([
            .init(mode: .clean, binding: preferences.cleanHotkey),
            .init(mode: .raw, binding: preferences.rawHotkey),
        ])
    }

    // MARK: - State

    private func handleStateChange(_ state: DictationState) {
        dictationState = state
        statusMessage = switch state {
        case .idle: "Ready"
        case .recording: "Recording"
        case .processing: "Processing"
        }
        if case .recording = state {} else { waveform = [] }
    }

    private func handleHUDChange(_ newHUD: HUDState) {
        hud = newHUD
        if case let .recording(level) = newHUD {
            waveform.append(level)
            if waveform.count > Self.waveformSampleCount {
                waveform.removeFirst(waveform.count - Self.waveformSampleCount)
            }
        }
    }

    // MARK: - Actions

    func toggleRecordingFromMenu() {
        Task { await controller.menuBarToggle() }
    }

    func refreshMicrophones() {
        microphones = AudioDeviceLister.inputDevices()
        // A hand-picked microphone that has disappeared falls back to System
        // Default until it comes back (PRD §11.1).
        if let selected = preferences.microphoneUniqueID,
           !microphones.contains(where: { $0.uniqueID == selected }) {
            statusMessage = "Microphone unavailable — using System Default"
        }
    }

    func refreshPermissions() {
        permissions = Dictionary(uniqueKeysWithValues: Permission.allCases.map { ($0, Permissions.isGranted($0)) })
    }

    func requestPermission(_ permission: Permission) async {
        _ = await Permissions.request(permission)
        refreshPermissions()
    }

    func refreshInstalledModels() async {
        installedSpeechModel = await modelManager.installedModel(kind: .speech)
        installedCleanupModel = await modelManager.installedModel(kind: .cleanup)
    }

    /// Downloads and activates a model, keeping the current one until the new
    /// one has validated (PRD §9.2, AC9).
    func install(_ descriptor: ModelDescriptor) async {
        installPhase[descriptor.id] = .downloading(fraction: 0)
        do {
            _ = try await modelManager.install(descriptor) { [weak self] phase in
                Task { @MainActor in self?.installPhase[descriptor.id] = phase }
            }
            await engines.invalidate(kind: descriptor.kind)
            await refreshInstalledModels()
        } catch {
            installPhase[descriptor.id] = .failed(needsManualRetry: true)
        }
    }

    func uninstallCleanupModel() async {
        await modelManager.uninstall(kind: .cleanup)
        await engines.invalidate(kind: .cleanup)
        installPhase.removeValue(forKey: ModelCatalog.defaultCleanupModel.id)
        installedCleanupModel.map { installPhase.removeValue(forKey: $0.id) }
        await refreshInstalledModels()
    }

    func completeOnboarding() {
        preferences.hasCompletedOnboarding = true
    }

    func openLogsFolder() {
        let directory = logger.directory
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        NSWorkspace.shared.open(directory)
    }
}

/// A mutable box so the dictation controller can read the latest preferences
/// from its own isolation domain without a reference back to `AppModel`.
final class PreferencesBox: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Preferences

    init(_ value: Preferences) { self.stored = value }

    var value: Preferences {
        get { lock.lock(); defer { lock.unlock() }; return stored }
        set { lock.lock(); defer { lock.unlock() }; stored = newValue }
    }
}

/// Sends each model kind to the downloader that knows how to fetch it.
struct KindRoutingDownloader: WaveCore.ModelDownloader {
    private let speech = WhisperModelDownloader()
    private let cleanup = MLXModelDownloader()

    func download(
        _ descriptor: ModelDescriptor,
        to destination: URL,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws {
        switch descriptor.kind {
        case .speech: try await speech.download(descriptor, to: destination, progress: progress)
        case .cleanup: try await cleanup.download(descriptor, to: destination, progress: progress)
        }
    }
}
