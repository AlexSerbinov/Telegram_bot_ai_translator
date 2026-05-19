import XCTest
@testable import TeycanTranslate

final class RealtimeEventDecoderTests: XCTestCase {

    private func decode(_ json: String, file: StaticString = #filePath, line: UInt = #line) throws -> RealtimeEvent {
        let data = Data(json.utf8)
        return try JSONDecoder().decode(RealtimeEvent.self, from: data)
    }

    // MARK: - Source transcript

    func test_inputTranscriptDelta_translationsApiName() throws {
        let event = try decode(#"{"type":"session.input_transcript.delta","delta":"Hola","item_id":"abc"}"#)
        guard case let .inputTranscriptDelta(itemID, delta) = event else {
            return XCTFail("expected .inputTranscriptDelta, got \(event)")
        }
        XCTAssertEqual(itemID, "abc")
        XCTAssertEqual(delta, "Hola")
    }

    func test_inputTranscriptDelta_conversationApiName() throws {
        let event = try decode(#"{"type":"conversation.item.input_audio_transcription.delta","delta":"Hola"}"#)
        guard case let .inputTranscriptDelta(_, delta) = event else {
            return XCTFail("expected .inputTranscriptDelta, got \(event)")
        }
        XCTAssertEqual(delta, "Hola")
    }

    func test_inputTranscriptCompleted_translationsApi() throws {
        let event = try decode(#"{"type":"session.input_transcript.completed","transcript":"Hola, ¿cómo estás?"}"#)
        guard case let .inputTranscriptCompleted(_, transcript) = event else {
            return XCTFail("expected .inputTranscriptCompleted, got \(event)")
        }
        XCTAssertEqual(transcript, "Hola, ¿cómo estás?")
    }

    func test_inputTranscriptCompleted_conversationApi() throws {
        let event = try decode(#"{"type":"conversation.item.input_audio_transcription.completed","transcript":"final"}"#)
        guard case let .inputTranscriptCompleted(_, transcript) = event else {
            return XCTFail("expected .inputTranscriptCompleted, got \(event)")
        }
        XCTAssertEqual(transcript, "final")
    }

    // MARK: - Translation output

    func test_outputTranscriptDelta_threeAliases() throws {
        for type in [
            "session.output_transcript.delta",
            "response.output_transcript.delta",
            "response.audio_transcript.delta",
            "response.output_audio_transcript.delta",
        ] {
            let event = try decode(#"{"type":"\#(type)","delta":"chunk"}"#)
            guard case let .outputTranscriptDelta(_, delta) = event else {
                return XCTFail("expected .outputTranscriptDelta for type=\(type)")
            }
            XCTAssertEqual(delta, "chunk")
        }
    }

    func test_outputTranscriptDone_aliases() throws {
        for type in [
            "session.output_transcript.completed",
            "response.output_transcript.completed",
            "response.audio_transcript.done",
            "response.output_audio_transcript.done",
        ] {
            let event = try decode(#"{"type":"\#(type)","transcript":"final"}"#)
            guard case let .outputTranscriptDone(_, transcript) = event else {
                return XCTFail("expected .outputTranscriptDone for type=\(type)")
            }
            XCTAssertEqual(transcript, "final")
        }
    }

    // MARK: - Free-form text

    func test_responseTextDelta_aliases() throws {
        for type in ["response.text.delta", "response.output_text.delta"] {
            let event = try decode(#"{"type":"\#(type)","delta":"some"}"#)
            guard case let .responseTextDelta(_, delta) = event else {
                return XCTFail("expected .responseTextDelta for type=\(type)")
            }
            XCTAssertEqual(delta, "some")
        }
    }

    // MARK: - Lifecycle

    func test_sessionCreated_isLifecycle() throws {
        let event = try decode(#"{"type":"session.created"}"#)
        if case .sessionCreated = event { return }
        XCTFail("expected .sessionCreated, got \(event)")
    }

    func test_sessionUpdated_isLifecycle() throws {
        let event = try decode(#"{"type":"session.updated"}"#)
        if case .sessionUpdated = event { return }
        XCTFail("expected .sessionUpdated, got \(event)")
    }

    func test_outputAudioBufferStarted() throws {
        let event = try decode(#"{"type":"output_audio_buffer.started"}"#)
        if case .outputAudioBufferStarted = event { return }
        XCTFail("expected .outputAudioBufferStarted, got \(event)")
    }

    func test_responseDone() throws {
        let event = try decode(#"{"type":"response.done"}"#)
        if case .responseDone = event { return }
        XCTFail("expected .responseDone, got \(event)")
    }

    // MARK: - Error

    func test_error_objectShape() throws {
        let event = try decode(#"{"type":"error","error":{"message":"boom","code":"E_BAD"}}"#)
        guard case let .error(message) = event else {
            return XCTFail("expected .error, got \(event)")
        }
        XCTAssertEqual(message, "boom")
    }

    func test_error_stringShape() throws {
        let event = try decode(#"{"type":"error","error":"plain string"}"#)
        guard case let .error(message) = event else {
            return XCTFail("expected .error, got \(event)")
        }
        XCTAssertEqual(message, "plain string")
    }

    func test_error_codeOnly() throws {
        let event = try decode(#"{"type":"error","error":{"code":"E_BAD"}}"#)
        guard case let .error(message) = event else {
            return XCTFail("expected .error, got \(event)")
        }
        XCTAssertEqual(message, "E_BAD")
    }

    // MARK: - Fallback

    func test_unknownType_fallsBackToOther() throws {
        let event = try decode(#"{"type":"future.event.kind","whatever":42}"#)
        guard case let .other(type, raw) = event else {
            return XCTFail("expected .other, got \(event)")
        }
        XCTAssertEqual(type, "future.event.kind")
        XCTAssertTrue(raw.contains("\"future.event.kind\""))
        XCTAssertTrue(raw.contains("42"))
    }

    // MARK: - Robustness

    func test_missingDelta_decodesAsEmptyString() throws {
        let event = try decode(#"{"type":"session.input_transcript.delta"}"#)
        guard case let .inputTranscriptDelta(_, delta) = event else {
            return XCTFail("expected .inputTranscriptDelta")
        }
        XCTAssertEqual(delta, "")
    }

    func test_invalidJSON_throws() {
        let bad = Data("not json".utf8)
        XCTAssertThrowsError(try JSONDecoder().decode(RealtimeEvent.self, from: bad))
    }

    func test_missingType_throws() {
        let data = Data(#"{"delta":"foo"}"#.utf8)
        XCTAssertThrowsError(try JSONDecoder().decode(RealtimeEvent.self, from: data))
    }
}
