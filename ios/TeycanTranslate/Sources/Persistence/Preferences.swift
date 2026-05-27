import Foundation

/// Centralized UserDefaults keys. Use `@AppStorage(Preferences.K.foo)` in views
/// for live binding, or `Preferences.shared.read/.write` from view models.
///
/// Phase 1: only namespacing; values added per feature in later phases.
enum Preferences {
    enum K {
        // Phrase tab
        static let voicePrimaryLang   = "voice.primaryLang"
        static let voiceSecondaryLang = "voice.secondaryLang"
        static let voiceSttProvider   = "voice.sttProvider"          // "elevenlabs" | "soniox"
        static let voiceTtsProvider   = "voice.ttsProvider"          // "elevenlabs" | "soniox"

        // Companion tab
        static let realtimeSourceLang = "realtime.src"
        static let realtimeTargetLang = "realtime.tgt"
        static let realtimeVolume     = "realtime.vol"

        // Bridge tab
        static let chatVoice              = "chat.voice"             // marin / cedar / alloy / ...
        static let chatInputLang          = "chat.lang"
        static let chatTranscribeModel    = "chat.transcribeModel"
        static let chatRoomMode           = "chat.roomMode"          // "0"/"1"
        static let chatVadThreshold       = "chat.vadThreshold"      // 0.1...0.9
        static let chatInstructionsKey    = "chat.instructions.v7"   // v7 drops the over-firing anti-echo rules so reverse-direction turns translate again

        // Bridge — explicit two-side language pair
        static let bridgeLangA = "bridge.langA"
        static let bridgeLangB = "bridge.langB"

        // Bridge — run Soniox real-time STT in parallel with gpt-realtime to
        // drive the user-side bubbles independently from OpenAI's transcription
        // model. Default ON (per user request).
        static let bridgeUseSoniox = "bridge.useSoniox"
        static let bridgeTranscriptProvider = "bridge.transcriptProvider"

        // Relay tab
        static let relayTtsProvider = "relay.ttsProvider"   // "elevenlabs" | "soniox"

        // App-wide
        static let lastSelectedTab = "app.lastTab"
    }
}
