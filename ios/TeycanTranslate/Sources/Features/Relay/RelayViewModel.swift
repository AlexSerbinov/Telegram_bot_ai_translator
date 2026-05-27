import Foundation
import Observation

@Observable
@MainActor
final class RelayViewModel {
    let manager = RelaySessionManager()
    /// Persisted Relay-tab settings (TTS provider, future toggles).
    let settings = RelaySettings()
    /// Persisted lang pair shared with Bridge — we read the same `bridgeLangA`/
    /// `bridgeLangB` keys so a swap in Bridge is reflected here (and vice versa).
    var langA: PhraseLanguage
    var langB: PhraseLanguage

    init() {
        let defaults = UserDefaults.standard
        let aCode = defaults.string(forKey: Preferences.K.bridgeLangA) ?? "uk"
        let bCode = defaults.string(forKey: Preferences.K.bridgeLangB) ?? "es"
        self.langA = PhraseLanguages.find(aCode) ?? PhraseLanguages.all[0]
        self.langB = PhraseLanguages.find(bCode) ?? PhraseLanguages.all[2]
    }

    func toggle() async {
        switch manager.phase {
        case .idle, .error:
            UserDefaults.standard.set(langA.code, forKey: Preferences.K.bridgeLangA)
            UserDefaults.standard.set(langB.code, forKey: Preferences.K.bridgeLangB)
            await manager.start(langA: langA.code, langB: langB.code)
        case .listening, .translating, .speaking, .starting:
            await manager.stop()
        }
    }

    func continueSession() {
        manager.continueSession()
    }

    var canCommitNow: Bool { manager.canCommitNow }

    func commitNow() async {
        await manager.commitNow()
    }

    var quotaWarning: String? { manager.quotaWarning }

    func dismissQuotaWarning() {
        manager.dismissQuotaWarning()
    }

    /// True when the system is working on a turn — Translating or speaking.
    /// Drives the spinning ring around the central mic so the user sees
    /// the work in flight after pressing "Done speaking" (or after the
    /// idle timer auto-committed).
    var isWorkingOnTurn: Bool {
        switch manager.phase {
        case .translating, .speaking: return true
        default: return false
        }
    }

    func replay(_ message: RelayMessage) async {
        await manager.replay(message: message)
    }

    func swapLanguages() {
        let a = langA
        langA = langB
        langB = a
        UserDefaults.standard.set(langA.code, forKey: Preferences.K.bridgeLangA)
        UserDefaults.standard.set(langB.code, forKey: Preferences.K.bridgeLangB)
    }

    var isRunning: Bool { manager.isRunning }

    var statusText: String {
        switch manager.phase {
        case .idle:         return "Tap mic to start"
        case .starting:     return "Connecting…"
        case .listening:    return remainingTimeText
        case .translating:  return "Translating…"
        // Half-duplex: mic stops capturing while the model speaks. Tell the
        // user explicitly — otherwise they speak during playback, words get
        // dropped, and it feels broken.
        case .speaking:     return "Speaking… (mic paused — wait for me to finish)"
        case .error(let m): return "Error: \(m)"
        }
    }

    /// True when the mic is "live" — capturing audio and feeding Soniox.
    /// False during translating/speaking/connecting so the UI can dim the
    /// mic button + show a clear non-interactable state.
    var micCapturing: Bool {
        if case .listening = manager.phase { return true }
        return false
    }

    private var remainingTimeText: String {
        guard let deadline = manager.deadline else { return "Live · listening" }
        let remaining = max(0, deadline.timeIntervalSinceNow)
        let m = Int(remaining) / 60
        let s = Int(remaining) % 60
        return String(format: "Live · %d:%02d", m, s)
    }
}
