import Foundation

/// Tunable parameters for `CostGuard`. Default values mirror the proven Mini App
/// numbers (3-min lifetime + 30s warn + 5s background grace). Tests pass
/// `.testFast` for sub-second timing.
struct CostGuardConfig: Sendable {
    /// Initial session lifetime — auto-stop after this elapsed.
    let baseLife: TimeInterval

    /// Each Continue press shifts the deadline forward by this amount.
    let extend: TimeInterval

    /// Show "Continue" banner this far before deadline.
    let warnLead: TimeInterval

    /// Watchdog tick — verifies no leaked WebRTC/mic when not running.
    let watchdogTick: TimeInterval

    /// If the app is backgrounded, give it this long before hardStop.
    let backgroundGrace: TimeInterval

    static let `default` = CostGuardConfig(
        baseLife: 180,
        extend: 120,
        warnLead: 30,
        watchdogTick: 5,
        backgroundGrace: 5
    )

    /// Sub-second values for unit tests — let scenarios complete in ~1s.
    static let testFast = CostGuardConfig(
        baseLife: 0.40,
        extend: 0.30,
        warnLead: 0.10,
        watchdogTick: 0.05,
        backgroundGrace: 0.05
    )
}
