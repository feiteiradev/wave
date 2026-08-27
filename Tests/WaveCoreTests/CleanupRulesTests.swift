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
}
