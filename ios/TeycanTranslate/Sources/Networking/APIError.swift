import Foundation

enum APIError: LocalizedError {
    case invalidResponse
    case httpStatus(Int, body: String)
    case decoding(any Error)
    case transport(any Error)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Server returned an invalid response."
        case .httpStatus(let code, let body):
            return "HTTP \(code): \(body)"
        case .decoding(let err):
            return "Decoding failed: \(err.localizedDescription)"
        case .transport(let err):
            return "Transport error: \(err.localizedDescription)"
        }
    }
}
