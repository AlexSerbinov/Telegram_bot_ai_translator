import Foundation

/// A single bubble in the Chat tab — either the user (input transcription) or
/// the assistant (response transcript). Mirrors the shape used by `BridgeMessage`
/// minus the language metadata, since Chat doesn't translate.
struct ChatMessage: Identifiable, Equatable {
    enum Role { case user, assistant }

    let id: String
    var role: Role
    var text: String
    var isFinalized: Bool
}
