import Foundation
import Observation

/// TTS provider available to the Phrase tab. The backend's `POST /api/tts`
/// accepts the raw string in its `provider` body field.
enum PhraseTtsProvider: String, CaseIterable, Identifiable {
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
        case .elevenlabs: return "Turbo v2.5 · MP3 · multilingual"
        case .soniox:     return "tts-rt-v1 · WAV 24 kHz · Maya voice"
        }
    }
}

/// Persisted, observable Phrase-tab preferences. UI binds directly; setters
/// mirror to UserDefaults. Mirrors the shape of `BridgeSettings` so future
/// per-tab settings (STT provider, voice, etc.) slot in the same way.
@Observable
@MainActor
final class PhraseSettings {
    var ttsProvider: PhraseTtsProvider {
        didSet { UserDefaults.standard.set(ttsProvider.rawValue, forKey: Preferences.K.voiceTtsProvider) }
    }

    init() {
        let raw = UserDefaults.standard.string(forKey: Preferences.K.voiceTtsProvider) ?? ""
        self.ttsProvider = PhraseTtsProvider(rawValue: raw) ?? .elevenlabs
    }
}
