import Foundation
import Observation

@Observable
@MainActor
final class CompanionViewModel {
    var targetLanguage: TargetLanguage = TargetLanguages.default
    let manager = CompanionSessionManager()

    init() {
        let savedCode = UserDefaults.standard.string(forKey: Preferences.K.realtimeTargetLang) ?? ""
        if let lang = TargetLanguages.find(savedCode) {
            self.targetLanguage = lang
        }
    }

    func toggle() async {
        switch manager.phase {
        case .idle, .error:
            UserDefaults.standard.set(targetLanguage.code, forKey: Preferences.K.realtimeTargetLang)
            await manager.start(targetLanguage: targetLanguage.code)
        case .running, .starting:
            await manager.stop()
        case .stopping:
            break
        }
    }

    func continueSession() {
        manager.extend()
    }

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
}
