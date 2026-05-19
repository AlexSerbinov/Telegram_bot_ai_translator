import XCTest
@testable import TeycanTranslate

final class DefaultPromptTests: XCTestCase {

    func test_uaToEs_isUkrainianSpanishMediator() {
        let p = DefaultPrompt.uaToEs
        XCTAssertTrue(p.contains("Ukrainian"))
        XCTAssertTrue(p.contains("Spanish"))
    }

    func test_makePrompt_parametricLanguagePair() {
        let p = DefaultPrompt.make(langA: "uk", langB: "en")
        XCTAssertTrue(p.contains("Ukrainian"))
        XCTAssertTrue(p.contains("English"))
        XCTAssertFalse(p.contains("Spanish"))
    }

    func test_makePrompt_thirdLanguagePairAlsoWorks() {
        let p = DefaultPrompt.make(langA: "de", langB: "fr")
        XCTAssertTrue(p.contains("German"))
        XCTAssertTrue(p.contains("French"))
    }

    func test_uaToEs_v9_dropsAntiEchoRules() {
        let p = DefaultPrompt.uaToEs
        XCTAssertNil(p.range(of: "Anti-echo", options: .caseInsensitive))
        XCTAssertNil(p.range(of: "Repetition guard", options: .caseInsensitive))
    }

    func test_uaToEs_v9_hasFullUtteranceRule() {
        let p = DefaultPrompt.uaToEs
        XCTAssertTrue(p.range(of: "FULL utterance", options: .caseInsensitive) != nil)
        XCTAssertTrue(p.range(of: "Never drop earlier content", options: .caseInsensitive) != nil)
    }

    func test_uaToEs_v9_handlesThirdLanguage() {
        let p = DefaultPrompt.uaToEs
        XCTAssertTrue(p.range(of: "third language", options: .caseInsensitive) != nil)
    }

    func test_uaToEs_v9_neverSpeakFirst() {
        // The "model thinks it's a chat partner on the first utterance" bug
        // fix: explicit "never speak first" + concrete banned phrases.
        let p = DefaultPrompt.uaToEs
        XCTAssertTrue(p.range(of: "never speak first", options: .caseInsensitive) != nil)
        XCTAssertTrue(p.range(of: "never greet", options: .caseInsensitive) != nil)
    }

    func test_uaToEs_v9_listsBannedAcknowledgements() {
        // Concrete examples of the conversational phrases the model must never
        // emit — anchors the abstract "no chat" instruction in concrete tokens.
        let p = DefaultPrompt.uaToEs
        XCTAssertTrue(p.contains("Hello"))
        XCTAssertTrue(p.contains("How can I help"))
    }

    func test_uaToEs_v9_strictTranslatorPreamble() {
        // The opening line must establish strict-translator role before any
        // other instruction — that's the model's primary anchor.
        let p = DefaultPrompt.uaToEs
        let firstHundred = String(p.prefix(120))
        XCTAssertTrue(firstHundred.contains("STRICT") || firstHundred.contains("strict"))
        XCTAssertTrue(firstHundred.range(of: "translator", options: .caseInsensitive) != nil)
    }

    func test_uaToEs_v9_silencePolicyForUnclearAudio() {
        // We must NOT instruct the model to ask "I didn't catch that" — that's
        // a chat response, not a translation. Verify the prompt explicitly
        // forbids it.
        let p = DefaultPrompt.uaToEs
        XCTAssertTrue(p.range(of: "didn't catch that", options: .caseInsensitive) != nil
                      || p.range(of: "didn’t catch that", options: .caseInsensitive) != nil)
    }
}
