import XCTest
@testable import TeycanTranslate

final class BridgeLanguageGuesserTests: XCTestCase {

    func test_cyrillicText_picksUkrainianSide() {
        let result = BridgeLanguageGuesser.guess(text: "Привіт, як справи?", langA: "uk", langB: "es")
        XCTAssertEqual(result, "uk")
    }

    func test_cyrillicText_picksCyrillicSideEvenWhenLangBIsCyrillic() {
        // When langA is Latin and langB is Cyrillic, Cyrillic text should land on langB.
        let result = BridgeLanguageGuesser.guess(text: "Привіт", langA: "es", langB: "uk")
        XCTAssertEqual(result, "uk")
    }

    func test_spanishDiacritics_pickSpanishSide() {
        let result = BridgeLanguageGuesser.guess(text: "¿Cómo estás hoy?", langA: "uk", langB: "es")
        XCTAssertEqual(result, "es")
    }

    func test_plainEnglish_picksNonCyrillicSide() {
        let result = BridgeLanguageGuesser.guess(text: "Good morning", langA: "uk", langB: "en")
        XCTAssertEqual(result, "en")
    }

    func test_mixedTextWithMajorityCyrillic_picksCyrillic() {
        let result = BridgeLanguageGuesser.guess(text: "Привіт hello", langA: "uk", langB: "es")
        XCTAssertEqual(result, "uk")
    }

    func test_emptyText_fallsBackToLangA() {
        let result = BridgeLanguageGuesser.guess(text: "", langA: "uk", langB: "es")
        XCTAssertEqual(result, "uk")
    }

    func test_whitespaceOnly_fallsBackToLangA() {
        let result = BridgeLanguageGuesser.guess(text: "    \n", langA: "uk", langB: "es")
        XCTAssertEqual(result, "uk")
    }

    func test_singleSpanishWord_withDiacritic_picksSpanish() {
        let result = BridgeLanguageGuesser.guess(text: "café", langA: "uk", langB: "es")
        XCTAssertEqual(result, "es")
    }

    func test_singleLatinWordWithoutHints_picksNonCyrillicLatin() {
        // No Cyrillic, no Spanish hints → Latin side wins.
        let result = BridgeLanguageGuesser.guess(text: "hello", langA: "uk", langB: "es")
        XCTAssertEqual(result, "es")
    }

    func test_oneCyrillicCharInLongLatinSentence_doesNotFlip() {
        // A single stray Cyrillic char shouldn't tip a long Latin sentence to
        // the Cyrillic side — the threshold is 30% Cyrillic.
        let text = "This is a long English sentence with one stray letter д"
        let result = BridgeLanguageGuesser.guess(text: text, langA: "uk", langB: "en")
        XCTAssertEqual(result, "en")
    }
}
