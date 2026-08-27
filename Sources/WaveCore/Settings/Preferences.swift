import Foundation

/// Everything the user can configure (PRD §30).
public struct Preferences: Codable, Sendable, Equatable {
    /// Global for both hotkeys (PRD §13).
    public var activationMode: ActivationMode
    public var cleanHotkey: HotkeyBinding
    public var rawHotkey: HotkeyBinding
    /// BCP-47. One language active at a time; no auto-detection (PRD §10).
    public var language: String
    /// `nil` means System Default (PRD §11.1).
    public var microphoneUniqueID: String?
    /// Whether Clean may use the local LLM. Clean still works without it (PRD §8).
    public var cleanupLLMEnabled: Bool
    /// How long Wave keeps its text on the clipboard before restoring (PRD §22.3).
    public var clipboardRetentionSeconds: Double
    /// How long the HUD lingers after a successful dictation (PRD §26.1).
    public var completionDisplaySeconds: Double
    /// How long an error stays on the HUD (PRD §29).
    public var errorDisplaySeconds: Double
    /// Unload the cleanup LLM after this much inactivity (PRD §8.1).
    public var cleanupModelIdleUnloadSeconds: Double
    public var launchAtLogin: Bool
    public var vocabulary: [VocabularyTerm]
    public var hasCompletedOnboarding: Bool

    public init(
        activationMode: ActivationMode = .pushToTalk,
        cleanHotkey: HotkeyBinding = .defaultClean,
        rawHotkey: HotkeyBinding = .defaultRaw,
        language: String = "pt-PT",
        microphoneUniqueID: String? = nil,
        cleanupLLMEnabled: Bool = true,
        clipboardRetentionSeconds: Double = 60,
        completionDisplaySeconds: Double = 1,
        errorDisplaySeconds: Double = 2.5,
        cleanupModelIdleUnloadSeconds: Double = 180,
        launchAtLogin: Bool = false,
        vocabulary: [VocabularyTerm] = [],
        hasCompletedOnboarding: Bool = false
    ) {
        self.activationMode = activationMode
        self.cleanHotkey = cleanHotkey
        self.rawHotkey = rawHotkey
        self.language = language
        self.microphoneUniqueID = microphoneUniqueID
        self.cleanupLLMEnabled = cleanupLLMEnabled
        self.clipboardRetentionSeconds = clipboardRetentionSeconds
        self.completionDisplaySeconds = completionDisplaySeconds
        self.errorDisplaySeconds = errorDisplaySeconds
        self.cleanupModelIdleUnloadSeconds = cleanupModelIdleUnloadSeconds
        self.launchAtLogin = launchAtLogin
        self.vocabulary = vocabulary
        self.hasCompletedOnboarding = hasCompletedOnboarding
    }

    /// Decoding tolerates a preferences file written by an older build: every
    /// key falls back to its default rather than failing the whole load.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = Preferences()
        func value<T: Decodable>(_ key: CodingKeys, _ fallback: T) -> T {
            (try? container.decode(T.self, forKey: key)) ?? fallback
        }
        activationMode = value(.activationMode, defaults.activationMode)
        cleanHotkey = value(.cleanHotkey, defaults.cleanHotkey)
        rawHotkey = value(.rawHotkey, defaults.rawHotkey)
        language = value(.language, defaults.language)
        microphoneUniqueID = try? container.decodeIfPresent(String.self, forKey: .microphoneUniqueID)
        cleanupLLMEnabled = value(.cleanupLLMEnabled, defaults.cleanupLLMEnabled)
        clipboardRetentionSeconds = value(.clipboardRetentionSeconds, defaults.clipboardRetentionSeconds)
        completionDisplaySeconds = value(.completionDisplaySeconds, defaults.completionDisplaySeconds)
        errorDisplaySeconds = value(.errorDisplaySeconds, defaults.errorDisplaySeconds)
        cleanupModelIdleUnloadSeconds = value(.cleanupModelIdleUnloadSeconds, defaults.cleanupModelIdleUnloadSeconds)
        launchAtLogin = value(.launchAtLogin, defaults.launchAtLogin)
        vocabulary = value(.vocabulary, defaults.vocabulary)
        hasCompletedOnboarding = value(.hasCompletedOnboarding, defaults.hasCompletedOnboarding)
    }

    public func hotkey(for mode: DictationMode) -> HotkeyBinding {
        mode == .clean ? cleanHotkey : rawHotkey
    }

    public func mode(for hotkey: HotkeyBinding) -> DictationMode? {
        if hotkey == cleanHotkey { return .clean }
        if hotkey == rawHotkey { return .raw }
        return nil
    }
}

/// Where preferences live. Abstracted so tests never touch the real defaults.
public protocol PreferencesStore: Sendable {
    func load() -> Preferences
    func save(_ preferences: Preferences)
}

/// JSON in `~/Library/Application Support/Wave/preferences.json`.
public final class FilePreferencesStore: PreferencesStore, @unchecked Sendable {
    private let url: URL
    private let lock = NSLock()

    public init(url: URL = FilePreferencesStore.defaultURL()) {
        self.url = url
    }

    public static func defaultURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Wave/preferences.json")
    }

    public func load() -> Preferences {
        lock.lock(); defer { lock.unlock() }
        guard let data = try? Data(contentsOf: url),
              let preferences = try? JSONDecoder().decode(Preferences.self, from: data)
        else { return Preferences() }
        return preferences
    }

    public func save(_ preferences: Preferences) {
        lock.lock(); defer { lock.unlock() }
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? JSONEncoder().encode(preferences).write(to: url, options: .atomic)
    }
}
