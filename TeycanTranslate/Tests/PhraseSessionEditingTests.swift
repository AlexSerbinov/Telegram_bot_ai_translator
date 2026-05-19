import XCTest
@testable import TeycanTranslate

@MainActor
final class PhraseSessionEditingTests: XCTestCase {

    func test_initialState_isIdle_emptyTexts() {
        let s = PhraseLiveSession()
        if case .idle = s.phase { /* ok */ } else { XCTFail("expected .idle") }
        XCTAssertEqual(s.sourceText, "")
        XCTAssertEqual(s.translation, "")
        XCTAssertNil(s.detectedLanguage)
    }

    func test_writingSourceTextWhileIdle_doesNotCrash() {
        // The didSet observer must not crash when a user types while session
        // is idle — debouncer will be scheduled but we don't fire any
        // network call here (translateAuto would need a mocked APIClient).
        let s = PhraseLiveSession()
        s.sourceText = "Hola mundo"
        XCTAssertEqual(s.sourceText, "Hola mundo")
    }

    func test_writingTranslationDirectly_setsValue() {
        let s = PhraseLiveSession()
        s.translation = "Manual override"
        XCTAssertEqual(s.translation, "Manual override")
    }

    func test_isRecording_startsFalse() {
        let s = PhraseLiveSession()
        XCTAssertFalse(s.isRecording)
    }

    func test_phaseEquatable_distinguishesErrorMessages() {
        let p1: PhraseLiveSession.Phase = .error("a")
        let p2: PhraseLiveSession.Phase = .error("b")
        let p3: PhraseLiveSession.Phase = .error("a")
        XCTAssertNotEqual(p1, p2)
        XCTAssertEqual(p1, p3)
    }

    func test_idleAndStartingPhase_areDistinct() {
        XCTAssertNotEqual(PhraseLiveSession.Phase.idle, .starting)
        XCTAssertNotEqual(PhraseLiveSession.Phase.translatingFinal, .speaking)
    }
}

@MainActor
final class PhraseViewModelTests: XCTestCase {

    override func setUp() async throws {
        try await super.setUp()
        UserDefaults.standard.removeObject(forKey: Preferences.K.voicePrimaryLang)
        UserDefaults.standard.removeObject(forKey: Preferences.K.voiceSecondaryLang)
    }

    func test_default_primaryIsUk_secondaryIsEs() {
        let vm = PhraseViewModel()
        XCTAssertEqual(vm.primaryLanguage.code, "uk")
        XCTAssertEqual(vm.secondaryLanguage.code, "es")
    }

    func test_swap_invertsPair() {
        let vm = PhraseViewModel()
        let oldPrimary = vm.primaryLanguage.code
        let oldSecondary = vm.secondaryLanguage.code
        vm.swapLanguages()
        XCTAssertEqual(vm.primaryLanguage.code, oldSecondary)
        XCTAssertEqual(vm.secondaryLanguage.code, oldPrimary)
    }

    func test_setPrimary_persistsToDefaults() {
        let vm = PhraseViewModel()
        vm.primaryLanguage = PhraseLanguages.find("en") ?? PhraseLanguages.all[0]
        XCTAssertEqual(
            UserDefaults.standard.string(forKey: Preferences.K.voicePrimaryLang),
            "en"
        )
    }

    func test_isTranslating_falseInIdle() {
        let vm = PhraseViewModel()
        XCTAssertFalse(vm.isTranslating)
    }

    func test_isRecording_falseInIdle() {
        let vm = PhraseViewModel()
        XCTAssertFalse(vm.isRecording)
    }

    func test_canSpeak_falseWithoutTranslation() {
        let vm = PhraseViewModel()
        XCTAssertFalse(vm.canSpeak)
    }

    func test_statusText_idleMessageMentionsPipeline() {
        let vm = PhraseViewModel()
        XCTAssertTrue(vm.statusText.contains("Soniox"))
        XCTAssertTrue(vm.statusText.contains("Groq"))
        XCTAssertTrue(vm.statusText.contains("ElevenLabs"))
    }
}
