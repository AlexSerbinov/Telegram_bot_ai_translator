import XCTest
@testable import TeycanTranslate

@MainActor
final class BridgeSettingsLangPairTests: XCTestCase {

    override func setUp() async throws {
        try await super.setUp()
        UserDefaults.standard.removeObject(forKey: Preferences.K.bridgeLangA)
        UserDefaults.standard.removeObject(forKey: Preferences.K.bridgeLangB)
    }

    func test_default_langA_isUkrainian() {
        let s = BridgeSettings()
        XCTAssertEqual(s.langA.code, "uk")
    }

    func test_default_langB_isSpanish() {
        let s = BridgeSettings()
        XCTAssertEqual(s.langB.code, "es")
    }

    func test_setLangA_persists() {
        let s = BridgeSettings()
        s.langA = PhraseLanguages.find("en") ?? PhraseLanguages.all[0]
        XCTAssertEqual(UserDefaults.standard.string(forKey: Preferences.K.bridgeLangA), "en")
    }

    func test_setLangB_persists() {
        let s = BridgeSettings()
        s.langB = PhraseLanguages.find("ru") ?? PhraseLanguages.all[0]
        XCTAssertEqual(UserDefaults.standard.string(forKey: Preferences.K.bridgeLangB), "ru")
    }

    func test_persistedLangs_loadOnInit() {
        UserDefaults.standard.set("en", forKey: Preferences.K.bridgeLangA)
        UserDefaults.standard.set("ru", forKey: Preferences.K.bridgeLangB)
        let s = BridgeSettings()
        XCTAssertEqual(s.langA.code, "en")
        XCTAssertEqual(s.langB.code, "ru")
    }

    func test_v7_instructionsKey_isCurrent() {
        // Ensures we did not regress to an older key version. v7 drops the
        // anti-echo / repetition rules from v6.
        XCTAssertEqual(Preferences.K.chatInstructionsKey, "chat.instructions.v7")
    }
}
