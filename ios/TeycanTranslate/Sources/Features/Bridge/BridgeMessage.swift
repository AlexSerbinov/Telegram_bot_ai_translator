import Foundation

/// A single transcript line in the Bridge tab — either what the user said
/// (transcribed via Soniox or gpt-4o-transcribe) or what the model spoke back.
struct BridgeMessage: Identifiable, Equatable {
    enum Role: String { case user, assistant }
    let id: String                  // OpenAI item_id; falls back to UUID if missing
    let role: Role
    var text: String
    var isFinalized: Bool
    /// Language code (`uk`, `es`, `en`, …) detected from the text. Bridge
    /// places the bubble on `langA`'s or `langB`'s side based on this value.
    var language: String?
    /// Wall-clock time the bubble was first opened. Used to render the MM:SS
    /// timestamp inside the V9 provenance trail of each archived turn card.
    var createdAt: Date = Date()

    static func placeholder(role: Role, itemID: String? = nil) -> BridgeMessage {
        BridgeMessage(
            id: itemID ?? UUID().uuidString,
            role: role,
            text: "",
            isFinalized: false,
            language: nil
        )
    }
}

/// Legacy alias — the actual implementation now lives in the shared
/// `LanguageGuesser` so Relay can reuse it without depending on Bridge.
typealias BridgeLanguageGuesser = LanguageGuesser
