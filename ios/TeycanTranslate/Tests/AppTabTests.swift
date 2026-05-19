import XCTest
@testable import TeycanTranslate

final class AppTabTests: XCTestCase {

    func test_threeTabs_existInOrder() {
        let cases = AppTab.allCases
        XCTAssertEqual(cases.count, 3)
        XCTAssertEqual(cases[0], .phrase)
        XCTAssertEqual(cases[1], .companion)
        XCTAssertEqual(cases[2], .bridge)
    }

    func test_titles_matchDESIGN_md() {
        XCTAssertEqual(AppTab.phrase.title,    "Phrase")
        XCTAssertEqual(AppTab.companion.title, "Companion")
        XCTAssertEqual(AppTab.bridge.title,    "Bridge")
    }

    func test_systemImages_areSFSymbols() {
        // Spot-check the SF Symbols we picked match the DESIGN.md mode metaphor.
        XCTAssertEqual(AppTab.phrase.systemImage,    "text.alignleft")
        XCTAssertEqual(AppTab.companion.systemImage, "waveform")
        XCTAssertEqual(AppTab.bridge.systemImage,    "arrow.left.arrow.right")
    }

    func test_rawValues_arePersistableLowercase() {
        XCTAssertEqual(AppTab.phrase.rawValue,    "phrase")
        XCTAssertEqual(AppTab.companion.rawValue, "companion")
        XCTAssertEqual(AppTab.bridge.rawValue,    "bridge")
    }
}
