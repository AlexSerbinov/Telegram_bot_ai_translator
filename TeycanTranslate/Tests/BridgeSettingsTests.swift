import XCTest
@testable import TeycanTranslate

@MainActor
final class BridgeSettingsTests: XCTestCase {

    /// Use an isolated UserDefaults suite so tests don't trample real prefs.
    private let suiteName = "com.teycan.tests.BridgeSettings"

    override func setUp() async throws {
        try await super.setUp()
        UserDefaults().removePersistentDomain(forName: suiteName)
        // The production BridgeSettings reads from `.standard` — clear the keys.
        for key in [
            Preferences.K.chatVoice,
            Preferences.K.chatInputLang,
            Preferences.K.chatTranscribeModel,
            Preferences.K.chatRoomMode,
            Preferences.K.chatVadThreshold,
            Preferences.K.chatInstructionsKey,
            Preferences.K.bridgeUseSoniox,
            Preferences.K.bridgeTranscriptProvider,
        ] {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    func test_defaults_matchMiniApp() {
        let s = BridgeSettings()
        XCTAssertEqual(s.voice, .marin)
        XCTAssertEqual(s.inputLanguage, .auto)
        XCTAssertEqual(s.transcriptionModel, .gpt4oTranscribe)
        XCTAssertEqual(s.transcriptProvider, .sonioxRealtime)
        XCTAssertEqual(s.roomMode, false)
        XCTAssertEqual(s.vadThreshold, 0.5, accuracy: 0.0001)
        // v9 prompt: strict-translator preamble + the "translation pipe" line.
        XCTAssertTrue(s.instructions.range(of: "strict", options: .caseInsensitive) != nil)
        XCTAssertTrue(s.instructions.range(of: "translator", options: .caseInsensitive) != nil)
    }

    func test_setVoice_persistsToUserDefaults() {
        let s = BridgeSettings()
        s.voice = .alloy
        XCTAssertEqual(UserDefaults.standard.string(forKey: Preferences.K.chatVoice), "alloy")
    }

    func test_setVadThreshold_persists() {
        let s = BridgeSettings()
        s.vadThreshold = 0.75
        XCTAssertEqual(UserDefaults.standard.double(forKey: Preferences.K.chatVadThreshold), 0.75)
    }

    func test_resetInstructions_returnsToDefaultPrompt() {
        let s = BridgeSettings()
        s.instructions = "garbage"
        s.resetInstructionsToDefault()
        XCTAssertEqual(s.instructions, DefaultPrompt.uaToEs)
    }

    func test_persistedInstructions_areLoadedOnInit() {
        UserDefaults.standard.set("custom prompt", forKey: Preferences.K.chatInstructionsKey)
        let s = BridgeSettings()
        XCTAssertEqual(s.instructions, "custom prompt")
    }

    func test_voiceCases_haveTenOptions() {
        XCTAssertEqual(BridgeVoice.allCases.count, 10)
        XCTAssertTrue(BridgeVoice.allCases.contains(.marin))
        XCTAssertTrue(BridgeVoice.allCases.contains(.cedar))
    }

    func test_inputLanguage_autoMapsToEmptyString() {
        // The server expects empty string for auto-detect.
        XCTAssertEqual(BridgeInputLanguage.auto.rawValue, "")
    }

    func test_transcriptProvider_persists() {
        let s = BridgeSettings()
        s.transcriptProvider = .gptRealtimeWhisper
        XCTAssertEqual(UserDefaults.standard.string(forKey: Preferences.K.bridgeTranscriptProvider), "gpt-realtime-whisper")
    }

    func test_legacyUseSonioxFalse_migratesToRealtimeWhisper() {
        UserDefaults.standard.set(false, forKey: Preferences.K.bridgeUseSoniox)
        let s = BridgeSettings()
        XCTAssertEqual(s.transcriptProvider, .gptRealtimeWhisper)
    }
}
