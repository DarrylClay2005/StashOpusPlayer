import AuthenticationServices
import Foundation
import SwiftUI

// MARK: - DiscordVerificationService
//
// Real Discord account verification (OAuth2 "identify" scope) — powers the
// "Discord Verified" badge next to the user's profile icon once linked.
// Distinct from the pre-existing Discord Rich Presence / Now Playing webhook
// settings (Settings → Integrations): those only need a client ID or a
// webhook URL the user pastes in themselves, neither of which proves account
// ownership. This actually round-trips through Discord's own OAuth2 consent
// screen via `ASWebAuthenticationSession` (never a plain `WKWebView`/Safari
// tab — the system session is the only way iOS lets an app observe the
// final `lumisound://discord-verify` redirect without the bridge needing a
// universal-link/app-association setup), with the authorization-code
// exchange itself happening server-side (see ios-bridge/main.py's
// /api/discord/oauth/callback) so the OAuth2 client secret never ships in
// the app binary.
@MainActor
final class DiscordVerificationService: NSObject, ObservableObject {
    static let shared = DiscordVerificationService()

    @Published private(set) var isVerified = false
    @Published private(set) var discordUsername: String?
    @Published private(set) var isLinking = false
    @Published var errorMessage: String?

    private weak var account: AccountService?
    private var authSession: ASWebAuthenticationSession?

    private override init() {
        super.init()
    }

    func attach(account: AccountService) {
        self.account = account
    }

    /// Refreshes `isVerified`/`discordUsername` from the bridge — call on
    /// launch (once logged in) and after `startVerification()` completes.
    func refresh() async {
        guard let account, account.isLoggedIn else {
            isVerified = false
            discordUsername = nil
            return
        }
        struct Response: Decodable {
            let verified: Bool
            let discord_username: String?
        }
        do {
            let data = try await account.makeRequest("/api/discord/verification")
            let decoded = try JSONDecoder().decode(Response.self, from: data)
            isVerified = decoded.verified
            discordUsername = decoded.discord_username
        } catch {
            // Best-effort — leaves whatever state was already loaded (e.g.
            // from a prior successful refresh this session) rather than
            // flipping the badge off on a transient network error.
            appWarn("DiscordVerificationService.refresh failed: \(error.localizedDescription)", category: "account")
        }
    }

    /// Starts the OAuth2 flow: fetches Discord's consent-screen URL from the
    /// bridge, presents it via `ASWebAuthenticationSession`, and — once the
    /// bridge's callback redirects to `lumisound://discord-verify` — re-fetches
    /// verification status to confirm it actually landed before flipping
    /// `isVerified`, rather than trusting the redirect's own `success=` query
    /// item alone (belt-and-suspenders: the redirect could in principle be
    /// intercepted/replayed by anything else that registers the same scheme).
    func startVerification(presentationContext: ASWebAuthenticationPresentationContextProviding) async {
        guard let account else { return }
        guard !isLinking else { return }
        errorMessage = nil
        isLinking = true
        defer { isLinking = false }

        struct StartResponse: Decodable { let authorize_url: String }
        let authorizeURL: URL
        do {
            let data = try await account.makeRequest("/api/discord/oauth/start")
            let decoded = try JSONDecoder().decode(StartResponse.self, from: data)
            guard let url = URL(string: decoded.authorize_url) else {
                errorMessage = "Couldn't start Discord verification."
                return
            }
            authorizeURL = url
        } catch let error as AccountError where error.statusCode == 503 {
            errorMessage = "Discord verification isn't configured on this server yet."
            return
        } catch {
            errorMessage = "Couldn't start Discord verification: \(error.localizedDescription)"
            return
        }

        let callbackScheme = "lumisound"
        let redirected: URL? = await withCheckedContinuation { continuation in
            let session = ASWebAuthenticationSession(
                url: authorizeURL,
                callbackURLScheme: callbackScheme
            ) { callbackURL, error in
                continuation.resume(returning: callbackURL)
            }
            session.presentationContextProvider = presentationContext
            // Discord's consent screen needs to work even for a Discord
            // account that isn't currently signed into Safari/the shared
            // cookie jar on-device — ephemeral avoids surfacing a stale/
            // wrong-account autofill from a previous session on this device.
            session.prefersEphemeralWebBrowserSession = true
            self.authSession = session
            if !session.start() {
                continuation.resume(returning: nil)
            }
        }
        authSession = nil

        guard let redirected else {
            // nil covers both "user cancelled" and "session failed to
            // start" — ASWebAuthenticationSession doesn't distinguish
            // those in a way worth surfacing as an error banner.
            return
        }

        let success = URLComponents(url: redirected, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == "success" })?.value == "true"
        if !success {
            let reason = URLComponents(url: redirected, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "reason" })?.value
            errorMessage = Self.errorMessage(forReason: reason)
            return
        }

        await refresh()
        if !isVerified {
            // The bridge reported success but our own re-check disagrees —
            // surface that rather than silently showing an unverified badge
            // with no explanation.
            errorMessage = "Discord confirmed the link, but verification didn't take — try again."
        }
    }

    func unlink() async {
        guard let account else { return }
        do {
            _ = try await account.makeRequest("/api/discord/verification", method: "DELETE")
            isVerified = false
            discordUsername = nil
        } catch {
            errorMessage = "Couldn't remove Discord verification: \(error.localizedDescription)"
        }
    }

    private static func errorMessage(forReason reason: String?) -> String? {
        switch reason {
        case "already_linked_elsewhere":
            return "That Discord account is already verified on a different Lumisound account."
        case "expired_state":
            return "That took too long — please try verifying again."
        case "access_denied":
            return nil  // user tapped Cancel on Discord's consent screen — not an error
        case .some:
            return "Discord verification didn't complete. Please try again."
        case .none:
            return "Discord verification didn't complete. Please try again."
        }
    }
}
