import SwiftUI

/// Top-level container. Wraps the tab view in an `AuthGate` that shows the
/// Sign in with Apple screen when no JWT is present.
struct AppRoot: View {
    var body: some View {
        AuthGate()
    }
}

#Preview {
    AppRoot()
}
