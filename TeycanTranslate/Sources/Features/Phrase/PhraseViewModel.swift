import Foundation
import Observation

/// Phrase tab view model. Owns a `PhraseLiveSession` (Soniox + Groq + ElevenLabs)
/// and exposes simple, UI-friendly state for `PhraseView`.
@Observable
@MainActor
final class PhraseViewModel {
    let session = PhraseLiveSession()
    let settings = PhraseSettings()

    var primaryLanguage: PhraseLanguage {
        didSet { UserDefaults.standard.set(primaryLanguage.code, forKey: Preferences.K.voicePrimaryLang) }
    }
    var secondaryLanguage: PhraseLanguage {
        didSet { UserDefaults.standard.set(secondaryLanguage.code, forKey: Preferences.K.voiceSecondaryLang) }
    }

    @ObservationIgnored
    private var tabObserver: NSObjectProtocol?

    init() {
        let defaults = UserDefaults.standard
        let primary = defaults.string(forKey: Preferences.K.voicePrimaryLang) ?? "uk"
        let secondary = defaults.string(forKey: Preferences.K.voicePrimaryLang).flatMap { _ in
            defaults.string(forKey: Preferences.K.voiceSecondaryLang)
        } ?? "es"
        self.primaryLanguage = PhraseLanguages.find(primary) ?? PhraseLanguages.all[0]
        self.secondaryLanguage = PhraseLanguages.find(secondary) ?? PhraseLanguages.all[2]

        // Auto-stop when user leaves Phrase tab — same cost-guard discipline as
        // Realtime / Chat. (Less critical here since Soniox + Groq are cheap,
        // but we still don't want a leaked WS.)
        tabObserver = NotificationCenter.default.addObserver(
            forName: .teycanTabChanged, object: nil, queue: .main
        ) { [weak self] notification in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let from = notification.userInfo?["from"] as? String
                if from == "phrase", self.session.isRecording {
                    await self.session.stop()
                }
            }
        }
    }

    var isRecording: Bool { session.isRecording }

    var isBusy: Bool {
        switch session.phase {
        case .starting, .translatingFinal, .speaking: return true
        case .idle, .recording, .error: return false
        }
    }

    var canSpeak: Bool {
        switch session.phase {
        case .idle: return !session.translation.isEmpty
        default:    return false
        }
    }

    var isTranslating: Bool {
        if case .translatingFinal = session.phase { return true }
        return false
    }

    var statusText: String {
        switch session.phase {
        case .idle:                return "Type or tap the mic — Soniox + Groq + ElevenLabs"
        case .starting:            return "Connecting to Soniox…"
        case .recording:           return session.detectedLanguage.map { "Recording (\($0))…" } ?? "Recording… tap stop"
        case .translatingFinal:    return "Translating…"
        case .speaking:            return "Speaking…"
        case .error(let m):        return "Error: \(m)"
        }
    }

    /// Force a one-shot translate of whatever's currently in `session.sourceText`
    /// — used by the "Translate" button on keyboard-only flows where the
    /// debouncer delay feels sluggish.
    func translateNow() async {
        await session.translateNow(
            primaryLanguage: primaryLanguage.code,
            secondaryLanguage: secondaryLanguage.code
        )
    }

    func toggleRecord() async {
        if session.isRecording {
            await session.stop()
        } else if case .idle = session.phase {
            await session.start(
                primaryLanguage: primaryLanguage.code,
                secondaryLanguage: secondaryLanguage.code
            )
        } else if case .error = session.phase {
            await session.start(
                primaryLanguage: primaryLanguage.code,
                secondaryLanguage: secondaryLanguage.code
            )
        }
    }

    func speakTranslation() async {
        await session.speakTranslation(provider: settings.ttsProvider)
    }

    func swapLanguages() {
        let p = primaryLanguage
        primaryLanguage = secondaryLanguage
        secondaryLanguage = p
    }
}
