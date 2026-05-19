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
}

struct TranscribeResponse: Decodable {
    let text: String
    let detectedLanguage: String?
    let confidence: Double?
}
