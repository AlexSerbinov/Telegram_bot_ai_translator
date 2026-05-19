import XCTest
@testable import TeycanTranslate

@MainActor
final class DiagLoggerTests: XCTestCase {

    /// The shared logger is a process-wide singleton, so individual tests must
    /// clear before & after to avoid polluting each other.
    override func setUp() async throws {
        try await super.setUp()
        DiagLogger.shared.clear()
    }

    override func tearDown() async throws {
        DiagLogger.shared.clear()
        try await super.tearDown()
    }

    func test_log_appendsEntry_eventually() async {
        DiagLogger.shared.log(.app, "hello world")
        // log() schedules a Task @MainActor; give the runloop a tick.
        await yieldUntil { DiagLogger.shared.entries.contains(where: { $0.message == "hello world" }) }
        XCTAssertTrue(DiagLogger.shared.entries.contains(where: { $0.message == "hello world" }))
    }

    func test_logTag_guardRendersAsString() async {
        DiagLogger.shared.log(.guard_, "limit hit")
        await yieldUntil { !DiagLogger.shared.entries.isEmpty }
        XCTAssertEqual(DiagLogger.shared.entries.first?.tag, "guard")
    }

    func test_clear_emptiesBuffer() async {
        DiagLogger.shared.log(.app, "x")
        await yieldUntil { !DiagLogger.shared.entries.isEmpty }
        DiagLogger.shared.clear()
        XCTAssertTrue(DiagLogger.shared.entries.isEmpty)
    }

    func test_snapshot_includesLoggedMessages() async {
        DiagLogger.shared.log(.net, "GET /api/foo")
        DiagLogger.shared.log(.rtc, "peer state → connecting")
        await yieldUntil { DiagLogger.shared.entries.count >= 2 }
        let snap = DiagLogger.shared.snapshot()
        XCTAssertTrue(snap.contains("[net] GET /api/foo"))
        XCTAssertTrue(snap.contains("[rtc] peer state → connecting"))
    }

    func test_ringBuffer_capsAt500Entries() async {
        for i in 0..<700 {
            DiagLogger.shared.log(.app, "msg \(i)")
        }
        await yieldUntil { DiagLogger.shared.entries.count == 500 }
        XCTAssertEqual(DiagLogger.shared.entries.count, 500)
        XCTAssertEqual(DiagLogger.shared.entries.first?.message, "msg 200")
        XCTAssertEqual(DiagLogger.shared.entries.last?.message, "msg 699")
    }

    // MARK: - Helpers

    private func yieldUntil(timeout: TimeInterval = 1.0, _ predicate: @MainActor () -> Bool) async {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if predicate() { return }
            try? await Task.sleep(nanoseconds: 5_000_000) // 5 ms
        }
    }
}
