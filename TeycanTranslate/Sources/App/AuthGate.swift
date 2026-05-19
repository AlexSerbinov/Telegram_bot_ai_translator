import SwiftUI

/// Routes between SignInView and MainTabView based on `AuthStore.isSignedIn`.
struct AuthGate: View {
    @State private var auth = AuthStore.shared

    var body: some View {
        Group {
            if auth.isSignedIn {
                MainTabView()
            } else {
                SignInView()
            }
        }
        .animation(.easeInOut(duration: 0.2), value: auth.isSignedIn)
    }
}

#Preview {
    AuthGate()
}
