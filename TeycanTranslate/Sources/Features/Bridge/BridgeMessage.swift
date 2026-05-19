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

/// Lightweight script-based language guesser for Bridge bubbles. Returns the
/// code of whichever Bridge side (`langA` / `langB`) is the better match —
/// Cyrillic text → the Cyrillic side, Spanish-flavoured text → the Spanish
/// side, otherwise the longer-text side wins. Good enough for UA↔ES,
/// UA↔EN, UA↔PT, ES↔EN. Falls back to `langA` when the text is empty.
enum BridgeLanguageGuesser {
    static func guess(text: String, langA: String, langB: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return langA }

        let cyrillicCount = trimmed.unicodeScalars.reduce(0) { acc, scalar in
            (0x0400...0x04FF).contains(scalar.value) ? acc + 1 : acc
        }
        let cyrillicShare = Double(cyrillicCount) / Double(max(trimmed.unicodeScalars.count, 1))

        let aCyrillic = isCyrillicLanguage(langA)
        let bCyrillic = isCyrillicLanguage(langB)

        if cyrillicShare > 0.3 {
            if aCyrillic { return langA }
            if bCyrillic { return langB }
        } else {
            // Latin text — Spanish wins over English/other if the message
            // contains Spanish-specific punctuation/diacritics.
            let spanishHints: Set<Character> = ["ñ", "Ñ", "¿", "¡", "á", "é", "í", "ó", "ú", "ü"]
            let looksSpanish = trimmed.contains(where: { spanishHints.contains($0) })
            if looksSpanish {
                if langA == "es" { return langA }
                if langB == "es" { return langB }
            }
            // Default: whichever side is NOT Cyrillic.
            if aCyrillic && !bCyrillic { return langB }
            if bCyrillic && !aCyrillic { return langA }
        }
        return langA
    }

    private static func isCyrillicLanguage(_ code: String) -> Bool {
        ["uk", "ru", "bg", "sr", "be", "mk"].contains(code)
    }
}
