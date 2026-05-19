import XCTest
@testable import TeycanTranslate

/// Mock URLProtocol that matches a small request → response table. Lets us
/// drive APIClient through URLSession without hitting the network.
final class MockURLProtocol: URLProtocol {
    nonisolated(unsafe) static var handler: ((URLRequest) -> (Data, HTTPURLResponse, Error?))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = MockURLProtocol.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
            return
        }
        let (data, response, error) = handler(request)
        if let error {
            client?.urlProtocol(self, didFailWithError: error)
            return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

@MainActor
final class APIClientTests: XCTestCase {

    private var client: APIClient!

    override func setUp() async throws {
        try await super.setUp()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: config)
        client = APIClient(session: session)
    }

    override func tearDown() async throws {
        MockURLProtocol.handler = nil
        client = nil
        try await super.tearDown()
    }

    // MARK: - realtimeSession

    func test_realtimeSession_decodesSuccessfulResponse() async throws {
        MockURLProtocol.handler = { req in
            XCTAssertEqual(req.httpMethod, "POST")
            XCTAssertTrue(req.url!.absoluteString.contains("/api/realtime/session"))
            XCTAssertEqual(req.value(forHTTPHeaderField: "Content-Type"), "application/json")
            let body = #"{"client_secret":"sk_eph_abc","expires_at":1234567890,"model":"gpt-realtime-translate"}"#
            return (Data(body.utf8), HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, nil)
        }
        let resp = try await client.realtimeSession(targetLanguage: "es")
        XCTAssertEqual(resp.client_secret, "sk_eph_abc")
        XCTAssertEqual(resp.expires_at, 1234567890)
        XCTAssertEqual(resp.model, "gpt-realtime-translate")
    }

    func test_realtimeSession_throwsOnNon2xx() async {
        MockURLProtocol.handler = { req in
            let body = "Bad target language"
            return (Data(body.utf8), HTTPURLResponse(url: req.url!, statusCode: 400, httpVersion: nil, headerFields: nil)!, nil)
        }
        do {
            _ = try await client.realtimeSession(targetLanguage: "xx")
            XCTFail("expected throw")
        } catch let err as APIError {
            if case let .httpStatus(code, body) = err {
                XCTAssertEqual(code, 400)
                XCTAssertEqual(body, "Bad target language")
            } else {
                XCTFail("expected .httpStatus, got \(err)")
            }
        } catch {
            XCTFail("expected APIError.httpStatus, got \(error)")
        }
    }

    func test_realtimeSession_throwsOnInvalidJSON() async {
        MockURLProtocol.handler = { req in
            return (Data("not json".utf8),
                    HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                    nil)
        }
        do {
            _ = try await client.realtimeSession(targetLanguage: "es")
            XCTFail("expected throw")
        } catch let err as APIError {
            if case .decoding = err { return }
            XCTFail("expected .decoding, got \(err)")
        } catch {
            XCTFail("expected APIError.decoding, got \(error)")
        }
    }

    func test_realtimeSession_sendsTargetLanguageInBody() async throws {
        let captured = AsyncStream<URLRequest>.makeStream()
        MockURLProtocol.handler = { req in
            captured.continuation.yield(req)
            captured.continuation.finish()
            let body = #"{"client_secret":"sk","expires_at":null,"model":"x"}"#
            return (Data(body.utf8), HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, nil)
        }
        _ = try await client.realtimeSession(targetLanguage: "ru")
        var iterator = captured.stream.makeAsyncIterator()
        guard let req = await iterator.next() else { return XCTFail("no request captured") }
        let bodyData = req.httpBodyStream.flatMap(Self.readAll) ?? req.httpBody ?? Data()
        let json = try JSONSerialization.jsonObject(with: bodyData) as? [String: Any]
        XCTAssertEqual(json?["targetLanguage"] as? String, "ru")
    }

    // MARK: - openaiSDPExchange

    func test_openaiSDPExchange_returnsAnswerSDP() async throws {
        MockURLProtocol.handler = { req in
            XCTAssertEqual(req.httpMethod, "POST")
            XCTAssertEqual(req.value(forHTTPHeaderField: "Authorization"), "Bearer sk_eph")
            XCTAssertEqual(req.value(forHTTPHeaderField: "Content-Type"), "application/sdp")
            let answer = "v=0\r\no=- 1 1 IN IP4 1.2.3.4\r\n"
            return (Data(answer.utf8),
                    HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                    nil)
        }
        let answer = try await client.openaiSDPExchange(
            url: URL(string: "https://example.com/sdp")!,
            clientSecret: "sk_eph",
            offerSDP: "v=0\r\noffer"
        )
        XCTAssertTrue(answer.starts(with: "v=0"))
    }

    func test_openaiSDPExchange_throwsOn401() async {
        MockURLProtocol.handler = { req in
            return (Data("expired".utf8),
                    HTTPURLResponse(url: req.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!,
                    nil)
        }
        do {
            _ = try await client.openaiSDPExchange(url: URL(string: "https://example.com/sdp")!,
                                                   clientSecret: "stale",
                                                   offerSDP: "v=0")
            XCTFail("expected throw")
        } catch let err as APIError {
            if case let .httpStatus(code, _) = err {
                XCTAssertEqual(code, 401)
            } else {
                XCTFail("expected .httpStatus, got \(err)")
            }
        } catch {
            XCTFail("expected APIError, got \(error)")
        }
    }

    // MARK: - realtimeChatSession

    func test_realtimeChatSession_postsAllParams() async throws {
        let captured = AsyncStream<URLRequest>.makeStream()
        MockURLProtocol.handler = { req in
            captured.continuation.yield(req)
            captured.continuation.finish()
            let body = #"{"client_secret":"sk","expires_at":null,"model":"gpt-realtime"}"#
            return (Data(body.utf8),
                    HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                    nil)
        }
        _ = try await client.realtimeChatSession(.init(
            voice: "marin",
            instructions: "be a translator",
            inputLanguage: "uk",
            roomMode: false,
            vadThreshold: 0.5,
            transcriptionModel: "gpt-4o-transcribe"
        ))
        var iterator = captured.stream.makeAsyncIterator()
        guard let req = await iterator.next() else { return XCTFail("no request") }
        let bodyData = req.httpBodyStream.flatMap(Self.readAll) ?? req.httpBody ?? Data()
        let json = try JSONSerialization.jsonObject(with: bodyData) as? [String: Any]
        XCTAssertEqual(json?["voice"] as? String, "marin")
        XCTAssertEqual(json?["instructions"] as? String, "be a translator")
        XCTAssertEqual(json?["inputLanguage"] as? String, "uk")
        XCTAssertEqual(json?["roomMode"] as? Bool, false)
        XCTAssertEqual(json?["vadThreshold"] as? Double, 0.5)
        XCTAssertEqual(json?["transcriptionModel"] as? String, "gpt-4o-transcribe")
    }

    // MARK: - Helpers

    private static func readAll(_ stream: InputStream) -> Data {
        var data = Data()
        stream.open()
        defer { stream.close() }
        let bufferSize = 1024
        var buffer = [UInt8](repeating: 0, count: bufferSize)
        while stream.hasBytesAvailable {
            let read = stream.read(&buffer, maxLength: bufferSize)
            if read <= 0 { break }
            data.append(buffer, count: read)
        }
        return data
    }
}
