import XCTest
@testable import TeycanTranslate

final class SlidingWindowMergerTests: XCTestCase {

    func test_initialMerge_acceptsFirstWindow() {
        var m = SlidingWindowMerger()
        let merged = m.merge("Hello world")
        XCTAssertEqual(merged, "Hello world")
        XCTAssertEqual(m.accumulated, "Hello world")
    }

    func test_emptyWindow_keepsAccumulated() {
        var m = SlidingWindowMerger()
        _ = m.merge("Hello")
        let merged = m.merge("")
        XCTAssertEqual(merged, "Hello")
    }

    func test_overlappingWindow_appendsOnlyNewSuffix() {
        var m = SlidingWindowMerger()
        _ = m.merge("Hello world")
        let merged = m.merge("world today")
        XCTAssertEqual(merged, "Hello world today")
    }

    func test_disjointWindow_appendsAll() {
        var m = SlidingWindowMerger()
        _ = m.merge("AAA")
        let merged = m.merge("BBB")
        XCTAssertEqual(merged, "AAABBB")
    }

    func test_repeatedIdenticalWindow_doesNotDuplicate() {
        var m = SlidingWindowMerger()
        _ = m.merge("привіт")
        let merged = m.merge("привіт")
        XCTAssertEqual(merged, "привіт")
    }

    func test_partialOverlap_singleWord() {
        var m = SlidingWindowMerger()
        _ = m.merge("один два три")
        let merged = m.merge("два три чотири")
        XCTAssertEqual(merged, "один два три чотири")
    }

    func test_reset_clearsAccumulated() {
        var m = SlidingWindowMerger()
        _ = m.merge("anything")
        m.reset()
        XCTAssertEqual(m.accumulated, "")
        XCTAssertEqual(m.merge("fresh start"), "fresh start")
    }
}
