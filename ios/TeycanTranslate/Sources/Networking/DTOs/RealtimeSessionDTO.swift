import Foundation

/// Request body for `POST /api/realtime/session`.
struct RealtimeSessionRequest: Codable {
    /// ISO 639-1 (e.g. "es", "ru", "en"). The OpenAI translation model emits
    /// audio + transcript in this language.
    let targetLanguage: String
}

/// Response from `POST /api/realtime/session`.
/// The `client_secret` is a short-lived (~60s TTL) ephemeral token suitable
/// for the SDP exchange with OpenAI. It must NEVER be persisted.
struct RealtimeSessionResponse: Decodable {
    let client_secret: String
    let expires_at: TimeInterval?
    let model: String
}

/// Request body for `POST /api/realtime-chat/session`.
struct RealtimeChatSessionRequest: Codable {
    let voice: String                    // marin, cedar, alloy, ...
    let instructions: String             // system prompt
    let inputLanguage: String            // empty string = auto-detect
    let roomMode: Bool                   // disables noise reduction + AEC
    let vadThreshold: Double             // 0.1...0.9
    let transcriptionModel: String?      // nil = no OpenAI input transcription
}

/// Response shape is identical to `RealtimeSessionResponse`.
typealias RealtimeChatSessionResponse = RealtimeSessionResponse
