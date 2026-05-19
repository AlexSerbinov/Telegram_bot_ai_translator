import Foundation

/// Represents a single event arriving on the OpenAI Realtime data channel
/// (`oai-events`). The full set of event types is large and continually
/// growing; we decode the ones we care about and fall back to `.other` for
/// anything unrecognised so a future server-side addition never crashes us.
enum RealtimeEvent: Decodable {
    /// Source language transcription (what the speaker said), streaming.
    case inputTranscriptDelta(itemID: String?, delta: String)
    /// Source language transcription completed.
    case inputTranscriptCompleted(itemID: String?, transcript: String)

    /// Translated audio's text representation, streaming.
    case outputTranscriptDelta(itemID: String?, delta: String)
    /// Translated audio's text representation completed.
    case outputTranscriptDone(itemID: String?, transcript: String)

    /// Free-form text response from the conversational model (Bridge tab).
    case responseTextDelta(itemID: String?, delta: String)

    /// Lifecycle / informational events.
    case sessionCreated
    case sessionUpdated
    case outputAudioBufferStarted
    /// `response.done` with the response's status — `"completed"`, `"cancelled"`,
    /// `"failed"`, etc. Cancelled responses fire when the user resumes speaking
    /// before the assistant finishes; we treat those as non-events for turn
    /// boundary purposes so a 70ms breath gap doesn't split one utterance into
    /// two bubbles.
    case responseDone(status: String)
    /// VAD detected the start of a user utterance — earliest server signal we
    /// can hook into to reserve a placeholder user bubble before the assistant
    /// starts streaming its translation.
    case inputAudioBufferSpeechStarted
    case inputAudioBufferSpeechStopped

    /// Server-reported error.
    case error(message: String)

    /// Anything we don't recognise — kept verbatim for logging.
    case other(type: String, raw: String)

    private enum CodingKeys: String, CodingKey {
        case type, delta, transcript, item_id, error, response
    }

    private struct ResponseBlock: Decodable {
        let status: String?
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let type = try c.decode(String.self, forKey: .type)
        let itemID = try c.decodeIfPresent(String.self, forKey: .item_id)

        switch type {
        case "session.input_transcript.delta",
             "conversation.item.input_audio_transcription.delta":
            let delta = (try? c.decode(String.self, forKey: .delta)) ?? ""
            self = .inputTranscriptDelta(itemID: itemID, delta: delta)

        case "session.input_transcript.completed",
             "conversation.item.input_audio_transcription.completed":
            let t = (try? c.decode(String.self, forKey: .transcript)) ?? ""
            self = .inputTranscriptCompleted(itemID: itemID, transcript: t)

        case "session.output_transcript.delta",
             "response.output_transcript.delta",
             "response.audio_transcript.delta",
             "response.output_audio_transcript.delta":
            let delta = (try? c.decode(String.self, forKey: .delta)) ?? ""
            self = .outputTranscriptDelta(itemID: itemID, delta: delta)

        case "session.output_transcript.completed",
             "response.output_transcript.completed",
             "response.audio_transcript.done",
             "response.output_audio_transcript.done":
            let t = (try? c.decode(String.self, forKey: .transcript)) ?? ""
            self = .outputTranscriptDone(itemID: itemID, transcript: t)

        case "response.text.delta",
             "response.output_text.delta":
            let delta = (try? c.decode(String.self, forKey: .delta)) ?? ""
            self = .responseTextDelta(itemID: itemID, delta: delta)

        case "session.created":
            self = .sessionCreated
        case "session.updated":
            self = .sessionUpdated
        case "output_audio_buffer.started":
            self = .outputAudioBufferStarted
        case "response.done":
            let status = (try? c.decode(ResponseBlock.self, forKey: .response))?.status ?? "unknown"
            self = .responseDone(status: status)
        case "input_audio_buffer.speech_started":
            self = .inputAudioBufferSpeechStarted
        case "input_audio_buffer.speech_stopped":
            self = .inputAudioBufferSpeechStopped

        case "error":
            // The error field can be a string or an object — capture it as JSON text.
            if let nested = try? c.decode(ErrorPayload.self, forKey: .error) {
                self = .error(message: nested.message ?? nested.code ?? "unknown")
            } else if let s = try? c.decode(String.self, forKey: .error) {
                self = .error(message: s)
            } else {
                self = .error(message: "unknown")
            }

        default:
            // Encode the raw JSON for diagnostic logging.
            let single = try decoder.singleValueContainer()
            let raw = (try? single.decode(JSONValue.self))?.jsonString ?? "{}"
            self = .other(type: type, raw: raw)
        }
    }

    private struct ErrorPayload: Decodable {
        let message: String?
        let code: String?
    }
}

/// Minimal JSON-any value used for `.other` raw payload preservation.
enum JSONValue: Decodable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case null
    case array([JSONValue])
    case object([String: JSONValue])

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null; return }
        if let v = try? c.decode(Bool.self) { self = .bool(v); return }
        if let v = try? c.decode(Double.self) { self = .number(v); return }
        if let v = try? c.decode(String.self) { self = .string(v); return }
        if let v = try? c.decode([JSONValue].self) { self = .array(v); return }
        if let v = try? c.decode([String: JSONValue].self) { self = .object(v); return }
        throw DecodingError.dataCorruptedError(in: c, debugDescription: "Unknown JSON value")
    }

    var jsonString: String {
        switch self {
        case .string(let s): return "\"\(s)\""
        case .number(let n): return String(n)
        case .bool(let b):   return b ? "true" : "false"
        case .null:          return "null"
        case .array(let a):  return "[" + a.map(\.jsonString).joined(separator: ",") + "]"
        case .object(let o):
            return "{" + o.map { "\"\($0.key)\":\($0.value.jsonString)" }.joined(separator: ",") + "}"
        }
    }
}
