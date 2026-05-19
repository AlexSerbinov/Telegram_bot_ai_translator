import AuthenticationServices
import SwiftUI

/// Sign in screen — clean wordmark, no mascot. Per DESIGN.md § Brand Mark.
struct SignInView: View {
    @State private var auth = AuthStore.shared
    @State private var coordinator = AppleAuthCoordinator()
    @State private var error: String?
    @State private var isLoading = false

    var body: some View {
        ZStack {
            DS.Color.bgCanvas.ignoresSafeArea()

            VStack(spacing: DS.Space.space2xl) {
                Spacer()

                // Editorial wordmark — letterspacing tight per DESIGN.md.
                VStack(spacing: DS.Space.sm) {
                    Text("teycan")
                        .font(DS.Font.displayL)
                        .tracking(DS.Tracking.titleTight)
                        .foregroundStyle(DS.Color.textInk)

                    EyebrowLabel(
                        text: "Translator for serious conversations",
                        color: DS.Color.textMuted,
                        leadingDash: true
                    )
                }

                Spacer()

                if let error {
                    Text(error)
                        .font(DS.Font.caption)
                        .foregroundStyle(DS.Color.error)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, DS.Space.xl)
                        .transition(.opacity)
                }

                SignInWithAppleButton(.signIn) { request in
                    request.requestedScopes = [.fullName, .email]
                } onCompletion: { _ in
                    // The native button is a visual anchor. Real flow runs
                    // through `coordinator.signIn()` via the overlay below.
                }
                .signInWithAppleButtonStyle(.black)
                .frame(height: 52)
                .padding(.horizontal, DS.Space.xl)
                .overlay(
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture { Task { await signIn() } }
                )
                .disabled(isLoading)

                #if DEBUG
                Button("Continue without sign-in (DEBUG)") {
                    auth.signIn(jwt: "", userId: "dev-anon", email: nil)
                }
                .font(DS.Font.caption)
                .foregroundStyle(DS.Color.textMuted)
                .padding(.bottom, DS.Space.md)
                #endif

                if isLoading {
                    ProgressView().tint(DS.Color.accent).padding(.bottom, DS.Space.lg)
                }
            }
            .padding(.bottom, DS.Space.space2xl)

            // Easter-egg paw print — bottom corner, very subtle. Per DESIGN.md
            // § Brand Mark — dog lives in storytelling, never on icon.
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    Image(systemName: "pawprint.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(DS.Color.accent.opacity(0.12))
                        .padding(.trailing, DS.Space.lg)
                        .padding(.bottom, DS.Space.lg)
                }
            }
            .accessibilityHidden(true)
        }
    }

    private func signIn() async {
        guard !isLoading else { return }
        isLoading = true
        error = nil
        defer { isLoading = false }
        do {
            let cred = try await coordinator.signIn()
            DiagLogger.shared.log(.auth, "Apple credential received (token \(cred.identityToken.count)B)")

            let response = try await AuthService.exchangeAppleToken(.init(
                identityToken: cred.identityToken,
                authorizationCode: cred.authorizationCode,
                fullName: .init(givenName: cred.givenName, familyName: cred.familyName)
            ))
            auth.signIn(jwt: response.token, userId: response.user.id, email: response.user.email)
        } catch {
            self.error = error.localizedDescription
            DiagLogger.shared.log(.auth, "sign-in failed: \(error.localizedDescription)")
        }
    }
}

#Preview {
    SignInView()
}
