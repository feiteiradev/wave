import Foundation
import Testing
import WaveCore
@testable import WavePlatform

@Suite("ModelCatalog")
struct ModelCatalogTests {
    @Test("every catalog entry has the kind of the list it is in")
    func kindsMatch() {
        #expect(ModelCatalog.speechModels.allSatisfy { $0.kind == .speech })
        #expect(ModelCatalog.cleanupModels.allSatisfy { $0.kind == .cleanup })
    }

    @Test("model ids are unique")
    func idsAreUnique() {
        let ids = (ModelCatalog.speechModels + ModelCatalog.cleanupModels).map(\.id)
        #expect(Set(ids).count == ids.count)
    }

    @Test("no English-only speech model is offered")
    func noEnglishOnlySpeechModels() {
        // PT-PT is the primary target, so `.en` and distil builds are excluded
        // — they cannot transcribe Portuguese at all (PRD §41).
        for model in ModelCatalog.speechModels {
            #expect(model.id.hasSuffix(".en") == false)
            #expect(model.id.contains("distil") == false)
        }
    }

    @Test("the defaults are present in their catalogs")
    func defaultsAreInCatalog() {
        #expect(ModelCatalog.speechModels.contains(ModelCatalog.defaultSpeechModel))
        #expect(ModelCatalog.cleanupModels.contains(ModelCatalog.defaultCleanupModel))
    }

    @Test("every model can be looked up by id")
    func lookupById() {
        for model in ModelCatalog.speechModels + ModelCatalog.cleanupModels {
            #expect(ModelCatalog.model(id: model.id)?.id == model.id)
        }
        #expect(ModelCatalog.model(id: "not-a-model") == nil)
    }

    @Test("Portuguese (Portugal) is the first offered language")
    func portugueseIsFirst() {
        #expect(ModelCatalog.languages.first?.code == "pt-PT")
        #expect(ModelCatalog.languages.first?.code == Preferences().language)
    }

    @Test("models(of:) returns the matching list")
    func modelsOfKind() {
        #expect(ModelCatalog.models(of: .speech) == ModelCatalog.speechModels)
        #expect(ModelCatalog.models(of: .cleanup) == ModelCatalog.cleanupModels)
    }
}

@Suite("WhisperKitSTTEngine")
struct WhisperLanguageTests {
    @Test("BCP-47 tags reduce to Whisper's bare language code")
    func reducesLanguageCode() {
        #expect(WhisperKitSTTEngine.whisperLanguageCode(for: "pt-PT") == "pt")
        #expect(WhisperKitSTTEngine.whisperLanguageCode(for: "pt-BR") == "pt")
        #expect(WhisperKitSTTEngine.whisperLanguageCode(for: "en-GB") == "en")
        #expect(WhisperKitSTTEngine.whisperLanguageCode(for: "es") == "es")
    }
}

@Suite("MLXCleanupEngine prompt")
struct CleanupPromptTests {
    @Test("the instructions name the dictated language")
    func namesLanguage() {
        let instructions = MLXCleanupEngine.instructions(for: "pt-PT")
        #expect(instructions.contains("Portuguese"))
    }

    @Test("the instructions forbid changing the meaning")
    func forbidsMeaningChange() {
        let instructions = MLXCleanupEngine.instructions(for: "pt-PT")
        #expect(instructions.contains("Never change the meaning"))
        #expect(instructions.contains("Never answer"))
        #expect(instructions.contains("Keep the original language"))
    }
}

@Suite("GlobalHotkeyMonitor")
struct HotkeyModifierTests {
    @Test("modifiers map to their Carbon masks")
    func mapsModifiers() {
        #expect(GlobalHotkeyMonitor.carbonModifiers([]) == 0)
        let option = GlobalHotkeyMonitor.carbonModifiers([.option])
        let optionShift = GlobalHotkeyMonitor.carbonModifiers([.option, .shift])
        #expect(option != 0)
        #expect(optionShift != option)
        #expect(optionShift & option == option)
    }

    @Test("the two default hotkeys are distinct")
    func defaultsAreDistinct() {
        #expect(HotkeyBinding.defaultClean != HotkeyBinding.defaultRaw)
        #expect(HotkeyBinding.defaultClean.displayString == "⌥Space")
        #expect(HotkeyBinding.defaultRaw.displayString == "⌥⇧Space")
    }
}
