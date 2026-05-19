import Foundation
import Observation

/// Process-wide auth state. The app JWT lives in Keychain; metadata about the
/// currently signed-in user lives here in memory + UserDefaults.
@Observable
@MainActor
final class AuthStore {
    static let shared = AuthStore()

    private static let jwtAccount = "app.jwt"
    private static let userIdKey  = "auth.userId"
    private static let emailKey   = "auth.email"

    private(set) var jwt: String?
    private(set) var userId: String?
    private(set) var email: String?

    var isSignedIn: Bool { jwt != nil }

    private init() {
        // Restore on launch.
        self.jwt = KeychainStore.string(for: Self.jwtAccount)
        self.userId = UserDefaults.standard.string(forKey: Self.userIdKey)
        self.email  = UserDefaults.standard.string(forKey: Self.emailKey)
    }

    func signIn(jwt: String, userId: String, email: String?) {
        KeychainStore.setString(jwt, for: Self.jwtAccount)
        UserDefaults.standard.set(userId, forKey: Self.userIdKey)
        if let email {
            UserDefaults.standard.set(email, forKey: Self.emailKey)
        } else {
            UserDefaults.standard.removeObject(forKey: Self.emailKey)
        }
        self.jwt = jwt
        self.userId = userId
        self.email = email
        DiagLogger.shared.log(.auth, "signed in: userId=\(userId)")
    }

    func signOut() {
        KeychainStore.delete(account: Self.jwtAccount)
        UserDefaults.standard.removeObject(forKey: Self.userIdKey)
        UserDefaults.standard.removeObject(forKey: Self.emailKey)
        self.jwt = nil
        self.userId = nil
        self.email = nil
        DiagLogger.shared.log(.auth, "signed out")
    }
}
