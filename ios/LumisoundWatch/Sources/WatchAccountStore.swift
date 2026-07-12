import Foundation
import SwiftUI

// MARK: - WatchAccountStore
//
// Persists the watch's own bridge session (bridge URL + bearer token) so the
// standalone "Watch Library" flow keeps working with no phone required after
// the first handoff or login. Two ways in:
//  1. Automatic handoff from the phone — see `PhoneWatchSync.pushAccountHandoffIfNeeded`
//     (iOS side) and `WatchConnectivityManager.apply` (this side, receives it).
//     This is the common case, since most users will already be logged into
//     the phone app.
//  2. Manual login on-watch (`WatchLoginView`) — for a watch used before the
//     phone app has ever logged in, or after an explicit on-watch logout.

@MainActor
final class WatchAccountStore: ObservableObject {
    static let shared = WatchAccountStore()

    private static let tokenKey = "watch_account_token"
    private static let bridgeURLKey = "watch_bridge_url"
    private static let usernameKey = "watch_account_username"

    /// Same public default as `StreamingService.defaultBridgeURL` on the phone
    /// (duplicated — not shared code, see WatchBridgeClient's header comment).
    static let defaultBridgeURL = "https://lumisound-bridge.xenusanimations.studio"

    @Published var isLoggedIn: Bool = false
    @Published var username: String = ""
    @Published var errorMessage: String?

    var token: String? {
        get { UserDefaults.standard.string(forKey: Self.tokenKey) }
        set { UserDefaults.standard.set(newValue, forKey: Self.tokenKey) }
    }

    var bridgeURL: String {
        get { UserDefaults.standard.string(forKey: Self.bridgeURLKey) ?? Self.defaultBridgeURL }
        set { UserDefaults.standard.set(newValue, forKey: Self.bridgeURLKey) }
    }

    private init() {
        username = UserDefaults.standard.string(forKey: Self.usernameKey) ?? ""
        isLoggedIn = token != nil
    }

    /// Applies a handoff pushed from the phone. A `nil`/empty token leaves any
    /// existing on-watch session alone (the phone may only be pushing a
    /// bridge-URL update); use `clearHandoff()` for an explicit sign-out.
    func applyHandoff(bridgeURL: String?, token: String?) {
        if let bridgeURL, !bridgeURL.isEmpty { self.bridgeURL = bridgeURL }
        guard let token, !token.isEmpty else { return }
        self.token = token
        isLoggedIn = true
    }

    /// The phone signed out — mirror that on-watch too, since a stale token
    /// left on an unattended wrist is a worse default than requiring re-login.
    func clearHandoff() {
        token = nil
        isLoggedIn = false
    }

    func login(username: String, password: String) async {
        errorMessage = nil
        let client = WatchBridgeClient(bridgeURL: bridgeURL, token: nil)
        do {
            let response = try await client.login(username: username, password: password)
            token = response.token
            self.username = username
            UserDefaults.standard.set(username, forKey: Self.usernameKey)
            isLoggedIn = true
        } catch {
            errorMessage = (error as? WatchBridgeError)?.message ?? error.localizedDescription
        }
    }

    func logout() {
        token = nil
        isLoggedIn = false
    }
}
