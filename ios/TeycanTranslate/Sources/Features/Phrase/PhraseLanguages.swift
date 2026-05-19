import Foundation

/// Languages the Phrase tab supports for input/output. Mirrors the Mini App's
/// dropdown set (uk/en/es/ka/id/ru/hu).
struct PhraseLanguage: Identifiable, Hashable {
    let code: String
    let name: String
    let flag: String
    var id: String { code }
}

enum PhraseLanguages {
    static let all: [PhraseLanguage] = [
        .init(code: "uk", name: "Українська",          flag: "🇺🇦"),
        .init(code: "en", name: "English",             flag: "🇺🇸"),
        .init(code: "es", name: "Español",             flag: "🇪🇸"),
        .init(code: "ru", name: "Русский",             flag: "🇷🇺"),
        .init(code: "id", name: "Bahasa Indonesia",    flag: "🇮🇩"),
        .init(code: "hu", name: "Magyar",              flag: "🇭🇺"),
        .init(code: "ka", name: "ქართული",            flag: "🇬🇪"),
    ]

    static func find(_ code: String) -> PhraseLanguage? {
        all.first { $0.code == code }
    }

    /// English name of a language code. Used inside system prompts where
    /// English is the most reliable label for the LLM to understand.
    static func englishName(_ code: String) -> String {
        switch code.lowercased() {
        case "uk": return "Ukrainian"
        case "en": return "English"
        case "es": return "Spanish"
        case "ru": return "Russian"
        case "id": return "Indonesian"
        case "hu": return "Hungarian"
        case "ka": return "Georgian"
        case "de": return "German"
        case "fr": return "French"
        case "it": return "Italian"
        case "pt": return "Portuguese"
        case "ja": return "Japanese"
        case "zh": return "Chinese"
        default:   return code.uppercased()
        }
    }
}
