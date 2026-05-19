import Foundation

/// Backend response from `POST /api/auth/apple`.
struct AppleAuthResponse: Decodable {
    let token: String
    let user: UserBlock

    struct UserBlock: Decodable {
        let id: String
        let email: String?
        let primaryLanguage: String
        let secondaryLanguage: String
    }
}

struct AppleAuthRequest: Encodable {
    let identityToken: String
    let authorizationCode: String?
    let fullName: NameBlock?

    struct NameBlock: Encodable {
        let givenName: String?
        let familyName: String?
    }
}

/// Networking for Apple Sign In. Talks to our server (NOT Apple directly —
/// that's handled by `AppleAuthCoordinator` on-device).
enum AuthService {
    static func exchangeAppleToken(_ request: AppleAuthRequest) async throws -> AppleAuthResponse {
        var req = URLRequest(url: Endpoints.baseURL.appending(path: "api/auth/apple"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder().encode(request)

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw APIError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            throw APIError.httpStatus(http.statusCode, body: String(data: data, encoding: .utf8) ?? "")
        }
        do {
            return try JSONDecoder().decode(AppleAuthResponse.self, from: data)
        } catch {
            throw APIError.decoding(error)
        }
    }
}
