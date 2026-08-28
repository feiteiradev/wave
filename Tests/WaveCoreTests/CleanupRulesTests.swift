import Testing
@testable import WaveCore

@Suite("CleanupRules")
struct CleanupRulesTests {
    private let rules = CleanupRules()

    @Test("collapses runs of whitespace")
    func collapsesWhitespace() {
        #expect(rules.apply(to: "Olá   mundo") == "Olá mundo")
    }

    @Test("removes the space before closing punctuation")
    func tightensPunctuation() {
        #expect(rules.apply(to: "Olá , tudo bem ?") == "Olá, tudo bem?")
    }

    @Test("inserts a space after punctuation when a word follows")
    func spacesAfterPunctuation() {
        #expect(rules.apply(to: "Bom dia.Como estás") == "Bom dia. Como estás")
    }

    @Test("leaves decimals and times intact")
    func preservesNumericPunctuation() {
        #expect(rules.apply(to: "são 10:30 e custa 3.14") == "São 10:30 e custa 3.14")
    }

    @Test("capitalizes the first letter and each new sentence")
    func capitalizesSentences() {
        #expect(rules.apply(to: "olá. tudo bem? sim!") == "Olá. Tudo bem? Sim!")
    }

    @Test("collapses an immediately repeated word")
    func collapsesStutter() {
        #expect(rules.apply(to: "o o carro está está pronto") == "O carro está pronto")
    }

    @Test("keeps a repeat that is not adjacent")
    func keepsNonAdjacentRepeats() {
        #expect(rules.apply(to: "o carro e o camião") == "O carro e o camião")
    }

    @Test("collapses a run of blank lines to one paragraph break")
    func keepsParagraphs() {
        #expect(rules.apply(to: "primeiro\n\n\nsegundo") == "Primeiro\n\nSegundo")
    }

    @Test("a single newline stays a single newline")
    func keepsSingleNewline() {
        #expect(rules.apply(to: "primeiro\nsegundo") == "Primeiro\nSegundo")
    }

    @Test("empty input stays empty")
    func emptyStaysEmpty() {
        #expect(rules.apply(to: "   ") == "")
    }

    @Test("does not invent a terminal period")
    func doesNotAddPunctuation() {
        #expect(rules.apply(to: "olá") == "Olá")
    }

    @Test("converts spoken punctuation to symbols in Portuguese")
    func convertsPortuguesePunctuation() {
        #expect(
            rules.apply(to: "isto é um teste ponto final agora outra frase vírgula com mais coisas")
                == "Isto é um teste. Agora outra frase, com mais coisas"
        )
    }

    @Test("converts spoken punctuation to symbols in English")
    func convertsEnglishPunctuation() {
        #expect(rules.apply(to: "hello comma world period") == "Hello, world.")
    }

    @Test("accepts the commands mid code-switch, both languages at once")
    func convertsAcrossLanguages() {
        #expect(rules.apply(to: "o payload está pronto comma finalmente ponto final") == "O payload está pronto, finalmente.")
    }

    @Test("matches a command spelled without its accent")
    func convertsWithoutAccent() {
        #expect(rules.apply(to: "primeiro virgula segundo") == "Primeiro, segundo")
    }

    @Test("takes the longest command, not a prefix of it")
    func prefersLongestCommand() {
        #expect(rules.apply(to: "olá ponto e vírgula adeus") == "Olá; adeus")
    }

    @Test("an article before the command keeps it literal")
    func determinerKeepsCommandLiteral() {
        #expect(rules.apply(to: "falta a vírgula nesta frase") == "Falta a vírgula nesta frase")
        #expect(rules.apply(to: "the period goes here") == "The period goes here")
    }

    @Test("leaves a bare ponto alone so file names survive")
    func leavesBarePontoAlone() {
        #expect(rules.apply(to: "o ficheiro chama-se readme ponto md") == "O ficheiro chama-se readme ponto md")
    }

    @Test("new line and new paragraph become breaks")
    func convertsLineBreaks() {
        #expect(rules.apply(to: "primeiro nova linha segundo") == "Primeiro\nSegundo")
        #expect(rules.apply(to: "primeiro novo parágrafo segundo") == "Primeiro\n\nSegundo")
    }

    @Test("absorbs the period Whisper already added after a spoken command")
    func absorbsDuplicateTerminator() {
        #expect(rules.apply(to: "isto é um teste ponto final.") == "Isto é um teste.")
    }
}
