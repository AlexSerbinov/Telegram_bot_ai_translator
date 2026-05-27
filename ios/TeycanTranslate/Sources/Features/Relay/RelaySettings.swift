import Foundation
import Observation

/// TTS provider available to the Relay tab. Mirrors `PhraseTtsProvider` but
/// kept separate so the two tabs can drift independently (e.g., Relay's
/// default leans toward ElevenLabs Flash for snappiness while Phrase can
/// stay on Turbo for quality).
enum RelayTtsProvider: String, CaseIterable, Identifiable {
    case elevenlabs
    case soniox

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .elevenlabs: return "ElevenLabs"
        case .soniox:     return "Soniox"
        }
    }

    var subtitle: String {
        switch self {
        case .elevenlabs: return "Flash v2.5 · MP3 · low latency (~75ms)"
        case .soniox:     return "tts-rt-v1 · WAV 24 kHz · slower start"
        }
    }
}

/// Persisted Relay-tab preferences. Only TTS provider for now; future-proofed
/// to grow the same way `BridgeSettings` / `PhraseSettings` do.
@Observable
@MainActor
final class RelaySettings {
    var ttsProvider: RelayTtsProvider {
        didSet { UserDefaults.standard.set(ttsProvider.rawValue, forKey: Preferences.K.relayTtsProvider) }
    }

    init() {
        let raw = UserDefaults.standard.string(forKey: Preferences.K.relayTtsProvider) ?? ""
        self.ttsProvider = RelayTtsProvider(rawValue: raw) ?? .elevenlabs
    }
}
