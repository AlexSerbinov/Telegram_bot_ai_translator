import Foundation
import Observation

@Observable
@MainActor
final class BridgeViewModel {
    let settings = BridgeSettings()
    let manager = BridgeSessionManager()

    var isRunning: Bool {
        switch manager.phase {
        case .running, .starting: return true
        case .idle, .stopping, .error: return false
        }
    }

    var statusText: String {
        switch manager.phase {
        case .idle:        return "Tap mic to start"
        case .starting:    return "Connecting…"
        case .running:     return remainingTimeText
        case .stopping:    return "Stopping…"
        case .error(let m): return "Error: \(m)"
        }
    }

    private var remainingTimeText: String {
        guard let deadline = manager.deadline else { return "Live" }
        let remaining = max(0, deadline.timeIntervalSinceNow)
        let m = Int(remaining) / 60
        let s = Int(remaining) % 60
        return String(format: "Live · %d:%02d", m, s)
    }

    func toggle() async {
        switch manager.phase {
        case .idle, .error:
            await manager.start(settings: settings)
        case .running, .starting:
            await manager.stop()
        case .stopping:
            break
        }
    }

    func continueSession() {
        manager.extend()
    }
}
