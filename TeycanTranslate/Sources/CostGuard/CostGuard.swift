import Foundation
import Observation
import UIKit

/// Reference-typed holder for NotificationCenter observers. Lives outside any
/// actor isolation so deinit can iterate observers safely. CostGuard stores
/// one of these as a `let` property — when CostGuard goes away, the bag's
/// own deinit fires and removes all observers.
private final class ObserverBag {
    var observers: [NSObjectProtocol] = []
    deinit {
        for o in observers {
            NotificationCenter.default.removeObserver(o)
        }
    }
}

/// 7-layer cost guard for OpenAI Realtime sessions. Mirrors the proven Mini App
/// pattern (Telegram). Owner registers `onWarn` / `onStop` callbacks and an
/// `isLeakedNow` predicate, then calls `start()` when the session begins and
/// `stop(.manual)` when the user presses Stop. All other kill triggers are
/// handled internally.
///
/// Why aggressive? OpenAI Realtime burns tokens fast. A leaked WebRTC peer
/// connection in the background = real money. Better to err on the side of
/// over-stopping; the user can always restart.
@Observable
@MainActor
final class CostGuard {
    enum StopReason: String, CustomStringConvertible {
        case manual
        case deadline
        case hidden5s
        case terminate
        case tabSwitch
        case pcFailed
        case pcClosed
        case watchdogLeak
        case errorOther
        var description: String { rawValue }
    }

    /// Set to true while a session is live.
    private(set) var isRunning: Bool = false
    /// Absolute deadline at which the session will auto-stop.
    private(set) var deadline: Date?
    /// True after the warn lead crossed but before deadline — UI shows the
    /// "Continue" banner.
    private(set) var inWarnWindow: Bool = false

    /// Caller-supplied callbacks.
    var onWarn: (@MainActor () -> Void)?
    var onStop: (@MainActor (StopReason) -> Void)?
    /// Returns true if WebRTC peer / mic resources are still alive. Used by
    /// the watchdog to detect leaks while !isRunning.
    var isLeakedNow: @MainActor () -> Bool = { false }

    private var warnTask: Task<Void, Never>?
    private var stopTask: Task<Void, Never>?
    private var watchdogTask: Task<Void, Never>?
    private var bgGraceTask: Task<Void, Never>?

    /// Held in a reference-counted bag so deinit (nonisolated) can release
    /// the NotificationCenter observers without touching MainActor state.
    @ObservationIgnored
    private let observerBag = ObserverBag()

    @ObservationIgnored
    let config: CostGuardConfig

    init(config: CostGuardConfig = .default) {
        self.config = config
        attachLifecycleObservers()
        startWatchdog()
    }

    // MARK: - Public API

    func start() {
        guard !isRunning else { return }
        isRunning = true
        inWarnWindow = false
        deadline = Date().addingTimeInterval(config.baseLife)
        rescheduleTimers()
        DiagLogger.shared.log(.guard_, "start: deadline = \(formatted(deadline!)) (3:00)")
    }

    /// Continue button — shifts deadline forward by `extend` from its current
    /// value (NOT from now). Matches Mini App "+2:00 to existing deadline".
    func extend() {
        guard isRunning, let d = deadline else { return }
        deadline = d.addingTimeInterval(config.extend)
        inWarnWindow = false
        rescheduleTimers()
        DiagLogger.shared.log(.guard_, "extend +\(Int(config.extend))s → \(formatted(deadline!))")
    }

    func stop(reason: StopReason) {
        guard isRunning else { return }
        isRunning = false
        inWarnWindow = false
        deadline = nil
        cancelSessionTasks()
        DiagLogger.shared.log(.guard_, "hardStop(\(reason))")
        onStop?(reason)
    }

    // MARK: - Internal

    private func rescheduleTimers() {
        warnTask?.cancel()
        stopTask?.cancel()
        guard let deadline else { return }
        let warnAt = deadline.addingTimeInterval(-config.warnLead)

        warnTask = Task { @MainActor [weak self] in
            try? await Self.sleep(until: warnAt)
            guard let self, self.isRunning, !Task.isCancelled else { return }
            self.inWarnWindow = true
            DiagLogger.shared.log(.guard_, "warn: 30s до автозупинки")
            self.onWarn?()
        }
        stopTask = Task { @MainActor [weak self] in
            try? await Self.sleep(until: deadline)
            guard let self, self.isRunning, !Task.isCancelled else { return }
            self.stop(reason: .deadline)
        }
    }

    private func cancelSessionTasks() {
        warnTask?.cancel(); warnTask = nil
        stopTask?.cancel(); stopTask = nil
        bgGraceTask?.cancel(); bgGraceTask = nil
    }

    private func startWatchdog() {
        let tickSeconds = config.watchdogTick
        watchdogTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(tickSeconds * 1_000_000_000))
                guard let self else { return }
                if !self.isRunning, self.isLeakedNow() {
                    DiagLogger.shared.log(.guard_, "watchdog detected leaked resources — forcing stop")
                    self.stop(reason: .watchdogLeak)
                }
            }
        }
    }

    private func attachLifecycleObservers() {
        let nc = NotificationCenter.default

        let resign = nc.addObserver(forName: UIApplication.willResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.isRunning else { return }
                let graceSeconds = self.config.backgroundGrace
                self.bgGraceTask?.cancel()
                self.bgGraceTask = Task { @MainActor [weak self] in
                    try? await Task.sleep(nanoseconds: UInt64(graceSeconds * 1_000_000_000))
                    guard let self, self.isRunning, !Task.isCancelled else { return }
                    if UIApplication.shared.applicationState != .active {
                        self.stop(reason: .hidden5s)
                    }
                }
            }
        }

        let active = nc.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.bgGraceTask?.cancel()
                self?.bgGraceTask = nil
            }
        }

        let terminate = nc.addObserver(forName: UIApplication.willTerminateNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.stop(reason: .terminate)
            }
        }

        observerBag.observers = [resign, active, terminate]
    }

    private static func sleep(until date: Date) async throws {
        let interval = date.timeIntervalSinceNow
        guard interval > 0 else { return }
        try await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
    }

    private func formatted(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f.string(from: date)
    }
}
