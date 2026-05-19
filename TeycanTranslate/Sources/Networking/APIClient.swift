import Foundation

/// Thin URLSession wrapper. Phase 2: anonymous (no auth) — the existing
/// backend endpoints accept unauthenticated requests just like the Telegram
/// Mini App. Phase 3 will inject a JWT from `AuthStore` here.
actor APIClient {
    static let shared = APIClient()

    private let session: URLSession
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(session: URLSession = .shared) {
        self.session = session
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
    }

    /// Reads the current app JWT from `AuthStore` (MainActor) for Authorization
    /// header injection. Returns nil for guest / DEBUG-bypass users — most
    /// existing endpoints still accept anonymous requests.
    private func currentJWT() async -> String? {
        await MainActor.run {
            let token = AuthStore.shared.jwt
            guard let token, !token.isEmpty else { return nil }
            return token
        }
    }

    /// Mints a short-lived OpenAI client_secret for the gpt-realtime-translate model.
    func realtimeSession(targetLanguage: String) async throws -> RealtimeSessionResponse {
        let body = RealtimeSessionRequest(targetLanguage: targetLanguage)
        return try await postJSON(url: Endpoints.realtimeSession, body: body)
    }

    /// Mints a short-lived OpenAI client_secret for the gpt-realtime conversational model.
    func realtimeChatSession(_ request: RealtimeChatSessionRequest) async throws -> RealtimeChatSessionResponse {
        try await postJSON(url: Endpoints.realtimeChatSession, body: request)
    }

    /// Ships a captured Bridge session WAV to the backend archive.
    /// `label` is a short tag like `bridge` / `phrase` to group recordings.
    /// When `sessionID` is supplied, the file is saved as `{sessionID}.wav`
    /// so the voice-log endpoints can link audio to transcript.
    @discardableResult
    func uploadRecording(wavURL: URL, deviceID: String, label: String, sessionID: String? = nil) async throws -> String {
        let data = try Data(contentsOf: wavURL)
        var req = URLRequest(url: Endpoints.recordings(deviceID: deviceID, label: label, sessionID: sessionID))
        req.httpMethod = "POST"
        req.setValue("audio/wav", forHTTPHeaderField: "Content-Type")
        req.httpBody = data
        let (responseData, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw APIError.httpStatus(status, body: String(data: responseData, encoding: .utf8) ?? "")
        }
        let body = String(data: responseData, encoding: .utf8) ?? ""
        return body
    }

    /// Push a batch of voice-log entries for a given session.
    func postVoiceLog(_ payload: VoiceLogPostRequest) async throws {
        var req = URLRequest(url: Endpoints.voiceLog)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 6
        req.httpBody = try encoder.encode(payload)
        let (_, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw APIError.httpStatus((response as? HTTPURLResponse)?.statusCode ?? -1, body: "")
        }
    }

    /// History tab — list recent voice-log sessions for this device.
    func voiceLogSessions(deviceID: String, limit: Int = 50) async throws -> VoiceLogSessionListDTO {
        var req = URLRequest(url: Endpoints.voiceLogSessions(deviceID: deviceID, limit: limit))
        req.httpMethod = "GET"
        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw APIError.httpStatus((response as? HTTPURLResponse)?.statusCode ?? -1, body: String(data: data, encoding: .utf8) ?? "")
        }
        return try decoder.decode(VoiceLogSessionListDTO.self, from: data)
    }

    /// History tab — full diarized transcript for one session.
    func voiceLogSession(_ sessionID: String, deviceID: String) async throws -> VoiceLogSessionDetailDTO {
        var req = URLRequest(url: Endpoints.voiceLogSession(sessionID, deviceID: deviceID))
        req.httpMethod = "GET"
        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw APIError.httpStatus((response as? HTTPURLResponse)?.statusCode ?? -1, body: String(data: data, encoding: .utf8) ?? "")
        }
        return try decoder.decode(VoiceLogSessionDetailDTO.self, from: data)
    }

    /// Phrase tab — fetch a temporary Soniox / ElevenLabs WS token from our backend.
    func sttToken() async throws -> String {
        var req = URLRequest(url: Endpoints.token)
        req.httpMethod = "GET"
        if let jwt = await currentJWT() {
            req.setValue("Bearer \(jwt)", forHTTPHeaderField: "Authorization")
        }
        do {
            let (data, response) = try await session.data(for: req)
            guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }
            guard (200..<300).contains(http.statusCode) else {
                throw APIError.httpStatus(http.statusCode, body: String(data: data, encoding: .utf8) ?? "")
            }
            struct TokenWrap: Decodable { let token: String }
            return try decoder.decode(TokenWrap.self, from: data).token
        } catch let err as APIError {
            throw err
        } catch {
            throw APIError.transport(error)
        }
    }

    /// Phrase tab — translate detected text to its language pair counterpart.
    func translateAuto(text: String, primaryLanguage: String, secondaryLanguage: String) async throws -> TranslateAutoResponse {
        try await postJSON(
            url: Endpoints.translateAuto,
            body: TranslateAutoRequest(text: text, primaryLanguage: primaryLanguage, secondaryLanguage: secondaryLanguage)
        )
    }

    /// Phrase tab — text-to-speech. Backend picks the engine from `provider`:
    /// "elevenlabs" → MP3 (audio/mpeg), "soniox" → WAV (audio/wav). Either is
    /// fed directly to AVAudioPlayer, no container-specific handling needed.
    func tts(text: String, language: String, provider: String? = nil) async throws -> Data {
        var req = URLRequest(url: Endpoints.tts)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let jwt = await currentJWT() {
            req.setValue("Bearer \(jwt)", forHTTPHeaderField: "Authorization")
        }
        req.httpBody = try encoder.encode(TTSRequest(text: text, language: language, provider: provider))
        do {
            let (data, response) = try await session.data(for: req)
            guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }
            guard (200..<300).contains(http.statusCode) else {
                throw APIError.httpStatus(http.statusCode, body: String(data: data, encoding: .utf8) ?? "")
            }
            return data
        } catch let err as APIError {
            throw err
        } catch {
            throw APIError.transport(error)
        }
    }

    /// Phrase tab — one-shot transcription of a recorded audio file.
    func transcribe(audioFile fileURL: URL, contentType: String = "audio/m4a", language: String = "auto") async throws -> TranscribeResponse {
        var url = Endpoints.voiceTranscribe
        if language != "auto" {
            var comps = URLComponents(url: url, resolvingAgainstBaseURL: false)!
            comps.queryItems = [URLQueryItem(name: "language", value: language)]
            url = comps.url!
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue(contentType, forHTTPHeaderField: "Content-Type")
        if let jwt = await currentJWT() {
            req.setValue("Bearer \(jwt)", forHTTPHeaderField: "Authorization")
        }
        let audioData = try Data(contentsOf: fileURL)
        req.httpBody = audioData
        do {
            let (data, response) = try await session.data(for: req)
            guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }
            guard (200..<300).contains(http.statusCode) else {
                throw APIError.httpStatus(http.statusCode, body: String(data: data, encoding: .utf8) ?? "")
            }
            do {
                return try decoder.decode(TranscribeResponse.self, from: data)
            } catch {
                throw APIError.decoding(error)
            }
        } catch let err as APIError {
            throw err
        } catch {
            throw APIError.transport(error)
        }
    }

    /// Posts the SDP offer to OpenAI's realtime endpoint and returns the answer SDP.
    /// The `clientSecret` is the ephemeral token from `realtimeSession()`.
    func openaiSDPExchange(url: URL, clientSecret: String, offerSDP: String) async throws -> String {
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(clientSecret)", forHTTPHeaderField: "Authorization")
        req.setValue("application/sdp", forHTTPHeaderField: "Content-Type")
        req.httpBody = Data(offerSDP.utf8)

        do {
            let (data, response) = try await session.data(for: req)
            guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }
            guard (200..<300).contains(http.statusCode) else {
                throw APIError.httpStatus(http.statusCode, body: String(data: data, encoding: .utf8) ?? "")
            }
            guard let sdp = String(data: data, encoding: .utf8) else { throw APIError.invalidResponse }
            return sdp
        } catch let err as APIError {
            throw err
        } catch {
            throw APIError.transport(error)
        }
    }

    private func postJSON<Body: Encodable, Response: Decodable>(url: URL, body: Body) async throws -> Response {
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let jwt = await currentJWT() {
            req.setValue("Bearer \(jwt)", forHTTPHeaderField: "Authorization")
        }
        req.httpBody = try encoder.encode(body)

        do {
            let (data, response) = try await session.data(for: req)
            guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }
            guard (200..<300).contains(http.statusCode) else {
                throw APIError.httpStatus(http.statusCode, body: String(data: data, encoding: .utf8) ?? "")
            }
            do {
                return try decoder.decode(Response.self, from: data)
            } catch {
                throw APIError.decoding(error)
            }
        } catch let err as APIError {
            throw err
        } catch {
            throw APIError.transport(error)
        }
    }
}
