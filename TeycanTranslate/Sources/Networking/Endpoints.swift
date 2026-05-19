import Foundation

enum BackendEnvironment {
    case production
    case localDev

    var baseURL: URL {
        switch self {
        case .production: return URL(string: "https://89-167-19-222.sslip.io")!
        case .localDev:   return URL(string: "http://localhost:3001")!
        }
    }
}

enum Endpoints {
    /// Simulator (Debug) → Mac `localhost:3001` (npm run dev). The simulator
    /// shares the host's loopback interface, so localhost works.
    ///
    /// Real iPhone (Debug or Release) → production HTTPS. On a physical
    /// device `localhost` resolves to the device itself, where no server is
    /// running — must use the public sslip.io URL.
    ///
    /// Override at runtime via `UserDefaults.standard.set("local"|"prod", forKey: "backend.env")`.
    static let environment: BackendEnvironment = {
        if let override = UserDefaults.standard.string(forKey: "backend.env") {
            return override == "prod" ? .production : .localDev
        }
        #if targetEnvironment(simulator)
        return .localDev
        #else
        return .production
        #endif
    }()

    static var baseURL: URL { environment.baseURL }

    static var realtimeSession: URL { baseURL.appending(path: "api/realtime/session") }
    static var realtimeChatSession: URL { baseURL.appending(path: "api/realtime-chat/session") }
    static var translateAuto: URL { baseURL.appending(path: "api/translate-auto") }
    static var tts: URL { baseURL.appending(path: "api/tts") }
    static var token: URL { baseURL.appending(path: "api/token") }
    static var voiceTranscribe: URL { baseURL.appending(path: "api/voice/transcribe") }
    static var logs: URL { baseURL.appending(path: "api/logs") }
    static var voiceLog: URL { baseURL.appending(path: "api/voice-log") }
    static func voiceLogSessions(deviceID: String, limit: Int = 50) -> URL {
        var c = URLComponents(url: baseURL.appending(path: "api/voice-log/sessions"), resolvingAgainstBaseURL: false)!
        c.queryItems = [
            URLQueryItem(name: "deviceID", value: deviceID),
            URLQueryItem(name: "limit", value: String(limit)),
        ]
        return c.url!
    }
    static func voiceLogSession(_ sessionID: String, deviceID: String) -> URL {
        var c = URLComponents(url: baseURL.appending(path: "api/voice-log/sessions/\(sessionID)"), resolvingAgainstBaseURL: false)!
        c.queryItems = [URLQueryItem(name: "deviceID", value: deviceID)]
        return c.url!
    }
    static func recordings(deviceID: String, label: String, sessionID: String? = nil) -> URL {
        var components = URLComponents(url: baseURL.appending(path: "api/recordings"), resolvingAgainstBaseURL: false)!
        var items = [
            URLQueryItem(name: "deviceID", value: deviceID),
            URLQueryItem(name: "label", value: label),
        ]
        if let sessionID, !sessionID.isEmpty {
            items.append(URLQueryItem(name: "sessionID", value: sessionID))
        }
        components.queryItems = items
        return components.url!
    }

    /// OpenAI direct WebRTC SDP endpoints. Audio + DataChannel events flow
    /// browser/iOS ↔ OpenAI without our server in the middle.
    enum OpenAI {
        static let translationsCalls = URL(string: "https://api.openai.com/v1/realtime/translations/calls")!
        static func calls(model: String) -> URL {
            var components = URLComponents(string: "https://api.openai.com/v1/realtime/calls")!
            components.queryItems = [URLQueryItem(name: "model", value: model)]
            return components.url!
        }
    }
}
