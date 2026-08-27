import Foundation
import Testing
@testable import WaveCore

@Suite("Preferences")
struct PreferencesTests {
    @Test("defaults match the PRD")
    func defaults() {
        let preferences = Preferences()
        #expect(preferences.language == "pt-PT")
        #expect(preferences.activationMode == .pushToTalk)
        #expect(preferences.microphoneUniqueID == nil)
        #expect(preferences.cleanHotkey == .defaultClean)
        #expect(preferences.rawHotkey == .defaultRaw)
        #expect(preferences.hasCompletedOnboarding == false)
    }

    @Test("survives a round trip through JSON")
    func roundTrips() throws {
        var preferences = Preferences()
        preferences.activationMode = .toggle
        preferences.language = "en-GB"
        preferences.vocabulary = [VocabularyTerm(term: "DearLift", aliases: ["dear lift"])]
        preferences.microphoneUniqueID = "AirPods"

        let data = try JSONEncoder().encode(preferences)
        let decoded = try JSONDecoder().decode(Preferences.self, from: data)
        #expect(decoded == preferences)
    }

    @Test("a preferences file missing keys falls back to defaults")
    func toleratesMissingKeys() throws {
        // Written by an older build that had fewer settings.
        let json = Data(#"{"language":"en-US"}"#.utf8)
        let decoded = try JSONDecoder().decode(Preferences.self, from: json)
        #expect(decoded.language == "en-US")
        #expect(decoded.activationMode == Preferences().activationMode)
        #expect(decoded.clipboardRetentionSeconds == Preferences().clipboardRetentionSeconds)
    }

    @Test("maps between hotkeys and modes")
    func mapsHotkeysToModes() {
        let preferences = Preferences()
        #expect(preferences.hotkey(for: .clean) == preferences.cleanHotkey)
        #expect(preferences.hotkey(for: .raw) == preferences.rawHotkey)
        #expect(preferences.mode(for: preferences.cleanHotkey) == .clean)
        #expect(preferences.mode(for: preferences.rawHotkey) == .raw)
        #expect(preferences.mode(for: HotkeyBinding(keyCode: 12, modifiers: [.command])) == nil)
    }

    @Test("a file store round trips through disk")
    func fileStoreRoundTrips() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("wave-prefs-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }

        let store = FilePreferencesStore(url: url)
        #expect(store.load() == Preferences())

        var preferences = Preferences()
        preferences.launchAtLogin = true
        store.save(preferences)
        #expect(store.load().launchAtLogin)
    }

    @Test("a corrupt preferences file falls back to defaults instead of crashing")
    func corruptFileFallsBack() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("wave-prefs-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        try Data("not json".utf8).write(to: url)

        #expect(FilePreferencesStore(url: url).load() == Preferences())
    }
}

@Suite("WaveError")
struct WaveErrorTests {
    @Test("every error has a short HUD message")
    func hudMessages() {
        for error in WaveError.allCases {
            #expect(error.hudMessage.isEmpty == false)
            // The HUD carries no diagnostics (PRD §29).
            #expect(error.hudMessage.count < 40)
        }
        #expect(WaveError.microphoneUnavailable.hudMessage == "Microphone unavailable")
    }
}
