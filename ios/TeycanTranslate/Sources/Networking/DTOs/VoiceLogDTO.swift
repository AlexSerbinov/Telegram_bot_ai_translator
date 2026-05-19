import Foundation

/// A single entry written to `/api/voice-log`. `human` entries come from
/// Soniox tokens (with a `speaker` id from diarization); `model` entries come
/// from `outputTranscriptDone` events on the gpt-realtime data channel.
/// `meta` is reserved for session start/end markers.
enum VoiceLogRole: String, Codable { case human, model, meta }

struct VoiceLogEntryDTO: Codable {
    let ts: Int64
    let role: VoiceLogRole
    let speaker: String?
    let lang: String?
    let text: String
}

struct VoiceLogPostRequest: Codable {
    let deviceID: String
    let sessionID: String
    /// Originating tab — `"bridge"`, `"companion"`, `"chat"`, `"phrase"`.
    /// Server captures the first non-empty `mode` it sees for a sessionID
    /// and returns it in the session list / detail so the History UI can
    /// label each session by mode.
    let mode: String?
    let entries: [VoiceLogEntryDTO]
}

/// Summary returned by `GET /api/voice-log/sessions`.
struct VoiceLogSessionSummaryDTO: Decodable, Identifiable {
    let sessionID: String
    let deviceID: String
    let startedAt: Int64
    let endedAt: Int64
    let entryCount: Int
    let recordingFile: String?
    let mode: String?

    var id: String { sessionID }
}

struct VoiceLogSessionListDTO: Decodable {
    let count: Int
    let sessions: [VoiceLogSessionSummaryDTO]
}

/// Detail returned by `GET /api/voice-log/sessions/:sessionID`.
struct VoiceLogSessionDetailDTO: Decodable {
    let sessionID: String
    let deviceID: String
    let startedAt: Int64
    let endedAt: Int64
    let recordingFile: String?
    let mode: String?
    let entries: [VoiceLogEntryDTO]
}
