import Foundation

/// Lightweight script-based language guesser. Returns whichever of two language
/// codes (`langA` / `langB`) is the better match for the given text.
///
/// Heuristic:
/// 1. If ≥30% of characters are Cyrillic → pick the Cyrillic side of the pair.
/// 2. Otherwise, Latin text — if it contains Spanish-specific characters
///    (`ñ`, `¿`, `¡`, accented vowels, `ü`) → pick the Spanish side.
/// 3. Otherwise, pick the non-Cyrillic side; fall back to `langA`.
///
/// Good enough for UA↔ES, UA↔EN, UA↔PT, ES↔EN. Used by both Bridge (as a
/// cross-check / OpenAI input-transcript classifier) and Relay (as a
/// bootstrap fallback when Soniox's per-token `language` field is still empty
/// on the very first tokens).
enum LanguageGuesser {
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
