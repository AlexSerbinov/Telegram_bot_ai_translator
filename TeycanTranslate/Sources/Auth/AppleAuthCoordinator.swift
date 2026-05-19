import AuthenticationServices
import Foundation
import UIKit

/// Bridges the legacy delegate-based `ASAuthorizationController` API to
/// `async/await`. Call `signIn()` once per user-tap; the returned
/// `AppleCredential` is exactly what `AuthService.exchangeAppleToken` needs.
struct AppleCredential {
    let identityToken: String
    let authorizationCode: String?
    let givenName: String?
    let familyName: String?
}

@MainActor
final class AppleAuthCoordinator: NSObject {
    func signIn() async throws -> AppleCredential {
        let request = ASAuthorizationAppleIDProvider().createRequest()
        request.requestedScopes = [.fullName, .email]

        let controller = ASAuthorizationController(authorizationRequests: [request])
        let proxy = AuthDelegateProxy()
        controller.delegate = proxy
        controller.presentationContextProvider = proxy

        return try await withCheckedThrowingContinuation { continuation in
            proxy.continuation = continuation
            // Retain the proxy until the flow finishes.
            proxy.holdSelf = proxy
            controller.performRequests()
        }
    }
}

/// Internal delegate that funnels Apple's callback into the continuation.
private final class AuthDelegateProxy: NSObject, ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {
    var continuation: CheckedContinuation<AppleCredential, Error>?
    var holdSelf: AuthDelegateProxy?

    func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        defer { holdSelf = nil }
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
              let tokenData = credential.identityToken,
              let token = String(data: tokenData, encoding: .utf8) else {
            continuation?.resume(throwing: NSError(
                domain: "AppleAuth", code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Missing Apple identityToken in credential"]
            ))
            continuation = nil
            return
        }
        let codeString: String? = credential.authorizationCode.flatMap { String(data: $0, encoding: .utf8) }
        let cred = AppleCredential(
            identityToken: token,
            authorizationCode: codeString,
            givenName: credential.fullName?.givenName,
            familyName: credential.fullName?.familyName
        )
        continuation?.resume(returning: cred)
        continuation = nil
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        defer { holdSelf = nil }
        continuation?.resume(throwing: error)
        continuation = nil
    }

    @MainActor
    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first(where: { $0.isKeyWindow }) ?? ASPresentationAnchor()
    }
}
