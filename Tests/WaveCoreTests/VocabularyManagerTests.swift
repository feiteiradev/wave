import Testing
@testable import WaveCore

@Suite("VocabularyManager")
struct VocabularyManagerTests {
    private let dearLift = VocabularyTerm(
        term: "DearLift",
        aliases: ["dear lift", "dear left", "deer lift"]
    )

    @Test("rewrites an alias to its canonical spelling")
    func rewritesAlias() {
        let manager = VocabularyManager(terms: [dearLift])
        #expect(manager.normalize("Vou trabalhar no dear lift hoje.") == "Vou trabalhar no DearLift hoje.")
    }

    @Test("matching ignores case")
    func ignoresCase() {
        let manager = VocabularyManager(terms: [dearLift])
        #expect(manager.normalize("O Dear Left está pronto") == "O DearLift está pronto")
    }

    @Test("only matches whole words")
    func wholeWordsOnly() {
        let manager = VocabularyManager(terms: [VocabularyTerm(term: "Wave", aliases: ["wav"])])
        #expect(manager.normalize("o ficheiro wavelength") == "o ficheiro wavelength")
    }

    @Test("prefers the longest matching alias")
    func longestAliasWins() {
        let manager = VocabularyManager(terms: [
            VocabularyTerm(term: "DearLift", aliases: ["dear lift"]),
            VocabularyTerm(term: "DearLiftPro", aliases: ["dear lift pro"]),
        ])
        #expect(manager.normalize("usa o dear lift pro") == "usa o DearLiftPro")
    }

    @Test("tolerates extra whitespace inside a multi-word alias")
    func toleratesInnerWhitespace() {
        let manager = VocabularyManager(terms: [dearLift])
        #expect(manager.normalize("o dear  lift") == "o DearLift")
    }

    @Test("an empty vocabulary leaves text untouched")
    func emptyVocabularyIsIdentity() {
        #expect(VocabularyManager().normalize("Olá, tudo bem?") == "Olá, tudo bem?")
    }

    @Test("exposes canonical terms as STT hotword hints")
    func exposesHotwords() {
        #expect(VocabularyManager(terms: [dearLift]).hotwords == ["DearLift"])
    }
}
