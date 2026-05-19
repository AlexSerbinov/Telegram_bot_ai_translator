import XCTest
@testable import TeycanTranslate

final class PhraseLanguagesTests: XCTestCase {

    func test_allLanguages_mirrorMiniAppDropdown() {
        let codes = Set(PhraseLanguages.all.map(\.code))
        let expected: Set<String> = ["uk", "en", "es", "ru", "id", "hu", "ka"]
        XCTAssertEqual(codes, expected)
    }

    func test_find_returnsExisting() {
        XCTAssertEqual(PhraseLanguages.find("uk")?.flag, "🇺🇦")
        XCTAssertEqual(PhraseLanguages.find("ka")?.name, "ქართული")
    }

    func test_find_nilForMissing() {
        XCTAssertNil(PhraseLanguages.find("zz"))
    }

    func test_languages_haveStableIds() {
        for l in PhraseLanguages.all {
            XCTAssertEqual(l.id, l.code)
        }
    }
}
