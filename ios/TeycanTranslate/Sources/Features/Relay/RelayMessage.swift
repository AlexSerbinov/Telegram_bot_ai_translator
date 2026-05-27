import Foundation

/// One bubble in the Relay tab's transcript stream. Either the user speaking
/// (sourced from Soniox STT) or the model speaking back (sourced from Groq
/// translation rendered via Soniox TTS). Roles are layered visually like in
/// Bridge but the data flow is one-shot per turn, not real-time.
struct RelayMessage: Identifiable, Equatable {
    enum Role: String { case user, model }

    let id: String
    var role: Role
    var text: String
    /// ISO 639-1 — `"uk"`, `"es"`, … For user bubbles, this is the detected
    /// source language. For model bubbles, this is the translation target.
    var language: String?
    var isFinalized: Bool
    /// True when the source language wasn't in the configured `langA`/`langB`
    /// pair (third-language case) and we fell back to default direction.
    /// UI shows a small "(detected: de — defaulting to ES)" hint on the
    /// bubble eyebrow.
    var wasFallback: Bool
    /// Wall-clock time the bubble was first opened.
    let createdAt: Date

    static func userPlaceholder(turnID: Int) -> RelayMessage {
        RelayMessage(
            id: "relay-user-\(turnID)",
            role: .user,
            text: "",
            language: nil,
            isFinalized: false,
            wasFallback: false,
            createdAt: Date()
        )
    }

    static func modelPlaceholder(turnID: Int) -> RelayMessage {
        RelayMessage(
            id: "relay-model-\(turnID)",
            role: .model,
            text: "",
            language: nil,
            isFinalized: false,
            wasFallback: false,
            createdAt: Date()
        )
    }
}
