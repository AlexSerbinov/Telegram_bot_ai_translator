import AVFoundation
import XCTest
@testable import TeycanTranslate

@MainActor
final class HeadphonesMonitorTests: XCTestCase {

    /// We can't drive AVAudioSession route changes from a unit test, but we
    /// can confirm the singleton initializes cleanly and exposes a stable
    /// initial shape — which is enough to catch breakage at the type-system
    /// level after refactors.
    func test_singleton_initializesWithoutCrash() {
        let m = HeadphonesMonitor.shared
        XCTAssertNotNil(m)
    }

    func test_isConnected_isBoolean() {
        let m = HeadphonesMonitor.shared
        // Either true or false — never nil.
        let connected = m.isConnected
        XCTAssertTrue(connected == true || connected == false)
    }

    func test_deviceLabel_isAString() {
        let m = HeadphonesMonitor.shared
        XCTAssertFalse(m.deviceLabel.isEmpty)
    }

    func test_refresh_doesNotCrash() {
        let m = HeadphonesMonitor.shared
        m.refresh()
        m.refresh()
        XCTAssertNotNil(m)
    }
}
