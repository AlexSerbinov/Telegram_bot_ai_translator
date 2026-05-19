import XCTest
@testable import TeycanTranslate

final class EndpointsTests: XCTestCase {

    /// On simulator, DEBUG resolves to localDev (Mac loopback) per
    /// `#if targetEnvironment(simulator)`. On a physical device DEBUG would
    /// resolve to production — but tests always run on simulator under our
    /// CI / local config, so we expect localDev here.
    func test_environment_simulatorPicksLocalDev() {
        XCTAssertEqual(Endpoints.environment.baseURL.scheme, "http")
        XCTAssertEqual(Endpoints.environment.baseURL.host, "localhost")
        XCTAssertEqual(Endpoints.environment.baseURL.port, 3001)
    }

    func test_realtimeSession_endpoint_path() {
        let url = Endpoints.realtimeSession
        XCTAssertEqual(url.path, "/api/realtime/session")
    }

    func test_realtimeChatSession_endpoint_path() {
        let url = Endpoints.realtimeChatSession
        XCTAssertEqual(url.path, "/api/realtime-chat/session")
    }

    func test_translateAuto_endpoint_path() {
        let url = Endpoints.translateAuto
        XCTAssertEqual(url.path, "/api/translate-auto")
    }

    func test_tts_endpoint_path() {
        XCTAssertEqual(Endpoints.tts.path, "/api/tts")
    }

    func test_token_endpoint_path() {
        XCTAssertEqual(Endpoints.token.path, "/api/token")
    }

    func test_voiceTranscribe_endpoint_path() {
        XCTAssertEqual(Endpoints.voiceTranscribe.path, "/api/voice/transcribe")
    }

    func test_openaiTranslationsCalls_isHTTPS() {
        XCTAssertEqual(Endpoints.OpenAI.translationsCalls.scheme, "https")
        XCTAssertEqual(Endpoints.OpenAI.translationsCalls.host, "api.openai.com")
        XCTAssertEqual(Endpoints.OpenAI.translationsCalls.path, "/v1/realtime/translations/calls")
    }

    func test_openaiCalls_includesModelQuery() {
        let url = Endpoints.OpenAI.calls(model: "gpt-realtime")
        XCTAssertEqual(url.host, "api.openai.com")
        XCTAssertTrue(url.absoluteString.contains("model=gpt-realtime"))
    }

    func test_productionURL_isSslip() {
        XCTAssertEqual(BackendEnvironment.production.baseURL.host, "89-167-19-222.sslip.io")
        XCTAssertEqual(BackendEnvironment.production.baseURL.scheme, "https")
    }

    func test_localDevURL_isLocalhost3001() {
        XCTAssertEqual(BackendEnvironment.localDev.baseURL.host, "localhost")
        XCTAssertEqual(BackendEnvironment.localDev.baseURL.port, 3001)
    }
}
