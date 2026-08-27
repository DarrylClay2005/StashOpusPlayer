import AuthenticationServices
import Foundation

// MARK: - AccountService+DiscordLogin
//
// "Sign in with Discord" from the LOGGED-OUT login screen — distinct from
// DiscordVerificationService.startVerification, which links Discord to an
// account you're ALREADY signed into. This one hits the bridge's
// unauthenticated /auth/discord/* pair, which either logs into an existing
// account previously linked via Discord verification or silently creates a
// brand new one on the fly, then hands back a normal session token exactly
// like /auth/login — so once this returns, `token`/`currentUser`/
// `isLoggedIn` are populated the same way a password login leaves them, and
// LoginView's existing post-login pullSync/avatar-load code needs no
// special-casing for how the session was obtained.
extension AccountService {

    /// Starts the OAuth2 flow: fetches Discord's consent-screen URL from the
    /// bridge, presents it via `ASWebAuthenticationSession`, and completes
    /// the resulting session — or, for an existing account with 2FA enabled,
    /// sets `pendingTOTPToken` exactly like `login()` does so the caller's
    /// existing TOTP-code UI (`completeTOTPLogin(code:)`) picks it up
    /// unmodified.
    func loginWithDiscord(presentationContext: ASWebAuthenticationPresentationContextProviding) async {
        errorMessage = nil
        pendingTOTPToken = nil
        appLog("Discord sign-in attempt", category: "account")

        struct StartResponse: Decodable { let authorize_url: String }
        let authorizeURL: URL
        do {
            let data = try await makeRequest("/auth/discord/start")
            let decoded = try JSONDecoder().decode(StartResponse.self, from: data)
            guard let url = URL(string: decoded.authorize_url) else {
                errorMessage = "Couldn't start Discord sign-in."
                return
            }
            authorizeURL = url
        } catch let error as AccountError where error.statusCode == 503 {
            errorMessage = "Discord sign-in isn't configured on this server yet."
            return
        } catch {
            errorMessage = "Couldn't start Discord sign-in: \(error.localizedDescription)"
            return
        }

        let callbackScheme = "lumisound"
        let redirected: URL? = await withCheckedContinuation { continuation in
            let session = ASWebAuthenticationSession(
                url: authorizeURL,
                callbackURLScheme: callbackScheme
            ) { callbackURL, _ in
                self.discordAuthSession = nil
                continuation.resume(returning: callbackURL)
            }
            session.presentationContextProvider = presentationContext
            // Same reasoning as DiscordVerificationService.startVerification —
            // never silently reuse a different Discord account that happens
            // to be cached in the shared cookie jar from a previous session
            // on this device.
            session.prefersEphemeralWebBrowserSession = true
            self.discordAuthSession = session
            if !session.start() {
                self.discordAuthSession = nil
                continuation.resume(returning: nil)
            }
        }

        guard let redirected else {
            // nil covers both "user cancelled" and "session failed to
            // start" — not worth surfacing as an error banner.
            return
        }

        let items = URLComponents(url: redirected, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func value(_ name: String) -> String? { items.first(where: { $0.name == name })?.value }

        guard value("success") == "true" else {
            errorMessage = Self.discordLoginErrorMessage(forReason: value("reason"))
            return
        }

        if value("requires_2fa") == "true", let pending = value("pending_token") {
            pendingTOTPToken = pending
            appLog("Discord sign-in requires 2FA code", category: "account")
            return
        }

        guard let sessionToken = value("token") else {
            errorMessage = "Discord confirmed sign-in, but no session was returned — try again."
            return
        }

        token = sessionToken
        do {
            let data = try await makeRequest("/auth/me")
            let user = try JSONDecoder().decode(AppUser.self, from: data)
            currentUser = user
            isLoggedIn = true
            hasDateOfBirth = user.dateOfBirth != nil
            saveUserLocally(user)
            appLog("Discord sign-in success: \(user.username) (id: \(user.id))", category: "account")
            await loadAvatar(forceRefresh: true)
            await refreshTOTPStatus()
        } catch {
            appError("Discord sign-in: fetching profile failed: \(error.localizedDescription)", category: "account")
            errorMessage = "Signed in, but couldn't load your profile — try again."
            token = nil
        }
    }

    private static func discordLoginErrorMessage(forReason reason: String?) -> String? {
        switch reason {
        case "account_disabled":
            return "That account has been disabled."
        case "expired_state":
            return "That took too long — please try signing in again."
        case "access_denied":
            return nil  // user tapped Cancel on Discord's consent screen — not an error
        default:
            return "Discord sign-in didn't complete. Please try again."
        }
    }
}
