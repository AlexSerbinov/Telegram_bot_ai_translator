import XCTest
@testable import TeycanTranslate

final class TargetLanguagesTests: XCTestCase {

    func test_default_isSpanish() {
        XCTAssertEqual(TargetLanguages.default.code, "es")
    }

    func test_find_existing() {
        XCTAssertEqual(TargetLanguages.find("ru")?.name, "Русский")
        XCTAssertEqual(TargetLanguages.find("ja")?.flag, "🇯🇵")
    }

    func test_find_missing_returnsNil() {
        XCTAssertNil(TargetLanguages.find("xx"))
        XCTAssertNil(TargetLanguages.find(""))
    }

    func test_supportedCount_matchesMiniApp() {
        // The Mini App and OpenAI gpt-realtime-translate currently support 13 languages.
        XCTAssertEqual(TargetLanguages.all.count, 13)
    }

    func test_supportedCodes_includeAllExpected() {
        let codes = Set(TargetLanguages.all.map(\.code))
        let expected: Set<String> = ["es","ru","en","pt","fr","de","it","ja","ko","zh","hi","id","vi"]
        XCTAssertEqual(codes, expected)
    }

    func test_uk_isNotSupported() {
        XCTAssertNil(TargetLanguages.find("uk"),
                     "Ukrainian is intentionally absent — model can't synthesize it yet.")
    }

    func test_languages_haveStableIds() {
        for lang in TargetLanguages.all {
            XCTAssertEqual(lang.id, lang.code)
        }
    }
}
