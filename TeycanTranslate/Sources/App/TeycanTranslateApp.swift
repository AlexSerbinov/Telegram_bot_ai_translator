import SwiftUI

@main
struct TeycanTranslateApp: App {
    @Environment(\.scenePhase) private var scenePhase

    init() {
        FontRegistration.registerJetBrainsMono()
        // Bootstrap remote logging *before* anything else — gives the
        // server-side ring buffer a heartbeat the moment the binary runs.
        DiagLogger.shared.log(.app, "🚀 TeycanTranslate launched (deviceID=\(RemoteLogger.shared.publicDeviceID))")

        // Auto-bypass auth when launched with `-bypass-auth 1` (used by smoke
        // tests / `xcrun simctl launch` automation). Lets the app land on
        // MainTabView immediately without an Apple Sign In flow.
        if ProcessInfo.processInfo.arguments.contains("-bypass-auth")
            || ProcessInfo.processInfo.environment["TEYCAN_BYPASS_AUTH"] == "1" {
            Task { @MainActor in
                if !AuthStore.shared.isSignedIn {
                    AuthStore.shared.signIn(jwt: "", userId: "dev-anon", email: nil)
                    DiagLogger.shared.log(.auth, "auth bypassed via launch flag")
                }
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            AppRoot()
                .onChange(of: scenePhase) { _, newPhase in
                    DiagLogger.shared.log(.app, "scenePhase → \(newPhase)")
                }
        }
    }
}
