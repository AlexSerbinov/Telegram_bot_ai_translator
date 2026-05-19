import Foundation

struct TargetLanguage: Identifiable, Hashable {
    let code: String
    let name: String
    let flag: String

    var id: String { code }
}

enum TargetLanguages {
    /// 13 languages supported by `gpt-realtime-translate` as confirmed in the
    /// Mini App. Ukrainian is intentionally absent — the model does not yet
    /// emit Ukrainian audio; users targeting UK content fall back to RU.
    static let all: [TargetLanguage] = [
        .init(code: "es", name: "Español",     flag: "🇪🇸"),
        .init(code: "ru", name: "Русский",     flag: "🇷🇺"),
        .init(code: "en", name: "English",     flag: "🇺🇸"),
        .init(code: "pt", name: "Português",   flag: "🇵🇹"),
        .init(code: "fr", name: "Français",    flag: "🇫🇷"),
        .init(code: "de", name: "Deutsch",     flag: "🇩🇪"),
        .init(code: "it", name: "Italiano",    flag: "🇮🇹"),
        .init(code: "ja", name: "日本語",       flag: "🇯🇵"),
        .init(code: "ko", name: "한국어",       flag: "🇰🇷"),
        .init(code: "zh", name: "中文",         flag: "🇨🇳"),
        .init(code: "hi", name: "हिन्दी",         flag: "🇮🇳"),
        .init(code: "id", name: "Indonesian",  flag: "🇮🇩"),
        .init(code: "vi", name: "Tiếng Việt",  flag: "🇻🇳"),
    ]

    static let `default` = all.first(where: { $0.code == "es" }) ?? all[0]

    static func find(_ code: String) -> TargetLanguage? {
        all.first(where: { $0.code == code })
    }
}
