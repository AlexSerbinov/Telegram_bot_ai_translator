import Foundation

struct TranslateAutoRequest: Encodable {
    let text: String
    let primaryLanguage: String
    let secondaryLanguage: String
}

struct TranslateAutoResponse: Decodable {
    let translation: String
    let detectedLanguage: String
    let targetLanguage: String
}

struct TTSRequest: Encodable {
    let text: String
    let language: String
    let provider: String?
    /// Optional ElevenLabs model override (`eleven_flash_v2_5` for low-latency,
    /// `eleven_turbo_v2_5` default). Ignored when `provider == "soniox"`.
    let model: String?
    /// When true, server pipes ElevenLabs ReadableStream straight to the
    /// HTTP response via chunked transfer instead of buffering the full
    /// MP3. Server-side latency win ~300-500ms.
    let stream: Bool?
}

struct TranscribeResponse: Decodable {
    let text: String
    let detectedLanguage: String?
    let confidence: Double?
}

/// `/api/translate-fast` — direct Groq call, dynamic from/to, low temperature.
/// Used by Relay tab. Doesn't auto-detect language; caller decides direction.
struct TranslateFastRequest: Encodable {
    let text: String
    let fromLanguage: String
    let toLanguage: String
}

struct TranslateFastResponse: Decodable {
    let translation: String
    let elapsedMs: Int?
}

/// Single SSE chunk from `/api/translate-fast-stream` — one word or token
/// fragment of the streaming translation. Concatenate in order.
struct TranslateStreamChunk: Decodable {
    let delta: String
}

/// One past turn passed as context to `/api/relay/completeness` so the
/// LLM can score the current partial WITH conversation context (e.g.
/// "Coffee" might be a complete answer if the prior model turn was
/// "Tea or coffee?", but incomplete on its own).
struct CompletenessTurn: Encodable {
    enum Role: String, Encodable { case user, model }
    let role: Role
    let lang: String?
    let text: String
}

/// `/api/relay/completeness` — quick Groq score 0.0-1.0 of how "complete"
/// the partial transcript looks IN CONTEXT. Used by Relay to adapt the
/// idle-commit timeout: high-completeness phrases commit faster.
struct CompletenessRequest: Encodable {
    let text: String
    let language: String
    let recentTurns: [CompletenessTurn]
}

struct CompletenessResponse: Decodable {
    let score: Double
    let elapsedMs: Int?
}

/// `/api/tts-quota` — provider availability snapshot returned at session
/// start so the Relay tab can warn the user if ElevenLabs is depleted or
/// the Soniox key is missing. ElevenLabs fields are pulled from the
/// `/v1/user/subscription` endpoint; Soniox has no public usage REST API,
/// so the server only checks that the key exists and defers real quota
/// failures to in-call error parsing.
struct TtsQuotaResponse: Decodable {
    struct Provider: Decodable {
        let ok: Bool
        let used: Int?
        let limit: Int?
        let remainingPct: Double?
        let message: String?
    }
    let elevenlabs: Provider
    let soniox: Provider
}
