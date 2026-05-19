import XCTest
@testable import TeycanTranslate

@MainActor
final class AuthStoreTests: XCTestCase {

    /// AuthStore writes to Keychain + UserDefaults globally — these tests
    /// drive the singleton through full sign-in / sign-out cycles.

    override func setUp() async throws {
        try await super.setUp()
        AuthStore.shared.signOut()
    }

    override func tearDown() async throws {
        AuthStore.shared.signOut()
        try await super.tearDown()
    }

    func test_initialState_isSignedOut() {
        XCTAssertFalse(AuthStore.shared.isSignedIn)
        XCTAssertNil(AuthStore.shared.jwt)
        XCTAssertNil(AuthStore.shared.userId)
    }

    func test_signIn_persistsThroughLifecycle() {
        AuthStore.shared.signIn(jwt: "tkn-xyz", userId: "u-123", email: "a@b.test")
        XCTAssertTrue(AuthStore.shared.isSignedIn)
        XCTAssertEqual(AuthStore.shared.jwt, "tkn-xyz")
        XCTAssertEqual(AuthStore.shared.userId, "u-123")
        XCTAssertEqual(AuthStore.shared.email, "a@b.test")
    }

    func test_signOut_clearsAll() {
        AuthStore.shared.signIn(jwt: "tkn", userId: "u", email: "e@x.test")
        AuthStore.shared.signOut()
        XCTAssertFalse(AuthStore.shared.isSignedIn)
        XCTAssertNil(AuthStore.shared.jwt)
        XCTAssertNil(AuthStore.shared.userId)
        XCTAssertNil(AuthStore.shared.email)
    }

    func test_appleAuthRequest_encodesShape() throws {
        let req = AppleAuthRequest(
            identityToken: "tk",
            authorizationCode: "code",
            fullName: .init(givenName: "Олександр", familyName: "Сербінов")
        )
        let data = try JSONEncoder().encode(req)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertEqual(json?["identityToken"] as? String, "tk")
        XCTAssertEqual(json?["authorizationCode"] as? String, "code")
        let name = json?["fullName"] as? [String: Any]
        XCTAssertEqual(name?["givenName"] as? String, "Олександр")
        XCTAssertEqual(name?["familyName"] as? String, "Сербінов")
    }

    func test_appleAuthResponse_decodesShape() throws {
        let body = #"{"token":"jwt-abc","user":{"id":"u-1","email":"a@b.test","primaryLanguage":"uk","secondaryLanguage":"es"}}"#
        let resp = try JSONDecoder().decode(AppleAuthResponse.self, from: Data(body.utf8))
        XCTAssertEqual(resp.token, "jwt-abc")
        XCTAssertEqual(resp.user.id, "u-1")
        XCTAssertEqual(resp.user.email, "a@b.test")
        XCTAssertEqual(resp.user.primaryLanguage, "uk")
        XCTAssertEqual(resp.user.secondaryLanguage, "es")
    }

    func test_appleAuthResponse_handlesNullEmail() throws {
        let body = #"{"token":"j","user":{"id":"u","email":null,"primaryLanguage":"uk","secondaryLanguage":"es"}}"#
        let resp = try JSONDecoder().decode(AppleAuthResponse.self, from: Data(body.utf8))
        XCTAssertNil(resp.user.email)
    }
}
