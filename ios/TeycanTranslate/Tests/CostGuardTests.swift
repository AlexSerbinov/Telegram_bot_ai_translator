import XCTest
@testable import TeycanTranslate

@MainActor
final class CostGuardTests: XCTestCase {

    func test_initialState_isIdle() {
        let guard_ = CostGuard(config: .testFast)
        XCTAssertFalse(guard_.isRunning)
        XCTAssertNil(guard_.deadline)
        XCTAssertFalse(guard_.inWarnWindow)
    }

    func test_start_setsDeadlineAndRunning() {
        let guard_ = CostGuard(config: .testFast)
        guard_.start()
        XCTAssertTrue(guard_.isRunning)
        XCTAssertNotNil(guard_.deadline)
        let interval = guard_.deadline!.timeIntervalSinceNow
        XCTAssertGreaterThan(interval, 0)
        XCTAssertLessThanOrEqual(interval, CostGuardConfig.testFast.baseLife + 0.05)
    }

    func test_manualStop_firesOnStop_withManualReason() async {
        let guard_ = CostGuard(config: .testFast)
        let exp = expectation(description: "onStop fires with .manual")
        guard_.onStop = { reason in
            XCTAssertEqual(reason, .manual)
            exp.fulfill()
        }
        guard_.start()
        guard_.stop(reason: .manual)
        await fulfillment(of: [exp], timeout: 0.5)
        XCTAssertFalse(guard_.isRunning)
        XCTAssertNil(guard_.deadline)
    }

    func test_startTwice_isIdempotent() {
        let guard_ = CostGuard(config: .testFast)
        guard_.start()
        let firstDeadline = guard_.deadline
        guard_.start() // ignored
        XCTAssertEqual(guard_.deadline, firstDeadline)
    }

    func test_stopWhenIdle_noOp() {
        let guard_ = CostGuard(config: .testFast)
        var fired = false
        guard_.onStop = { _ in fired = true }
        guard_.stop(reason: .manual)
        XCTAssertFalse(fired)
    }

    func test_warn_firesBeforeDeadline() async {
        let guard_ = CostGuard(config: .testFast)
        let warned = expectation(description: "onWarn fires")
        let stopped = expectation(description: "onStop fires")
        guard_.onWarn = { warned.fulfill() }
        guard_.onStop = { _ in stopped.fulfill() }
        guard_.start()
        await fulfillment(of: [warned, stopped], timeout: 1.0, enforceOrder: true)
    }

    func test_extend_shiftsDeadlineForward() {
        let guard_ = CostGuard(config: .testFast)
        guard_.start()
        let before = guard_.deadline!
        guard_.extend()
        let after = guard_.deadline!
        let delta = after.timeIntervalSince(before)
        XCTAssertEqual(delta, CostGuardConfig.testFast.extend, accuracy: 0.01)
        XCTAssertFalse(guard_.inWarnWindow)
    }

    func test_extend_whenIdle_noOp() {
        let guard_ = CostGuard(config: .testFast)
        guard_.extend()
        XCTAssertNil(guard_.deadline)
    }

    func test_deadlineFires_callsOnStop_withDeadlineReason() async {
        let guard_ = CostGuard(config: .testFast)
        let exp = expectation(description: "deadline auto-stop")
        guard_.onStop = { reason in
            XCTAssertEqual(reason, .deadline)
            exp.fulfill()
        }
        guard_.start()
        await fulfillment(of: [exp], timeout: 1.0)
    }

    func test_extend_pushesDeadlineFiringFurther() async {
        let guard_ = CostGuard(config: .testFast)
        guard_.start()

        // After ~halfway through baseLife, extend.
        try? await Task.sleep(nanoseconds: UInt64(CostGuardConfig.testFast.baseLife * 0.5 * 1_000_000_000))
        guard_.extend()

        // Now wait beyond the original baseLife — guard should still be running.
        try? await Task.sleep(nanoseconds: UInt64(CostGuardConfig.testFast.baseLife * 0.6 * 1_000_000_000))
        XCTAssertTrue(guard_.isRunning, "extend() should have pushed the stop past original deadline")

        // Finally let the extended deadline expire.
        try? await Task.sleep(nanoseconds: UInt64((CostGuardConfig.testFast.extend + 0.2) * 1_000_000_000))
        XCTAssertFalse(guard_.isRunning)
    }
}
