import Foundation
import SwiftUI
import UIKit

extension AccountService {

    // MARK: - Scrobbling

    /// Fetches whether the user has Last.fm/ListenBrainz scrobbling linked.
    func fetchScrobbleLinks() async -> ScrobbleLinks? {
        guard isLoggedIn else { return nil }
        do {
            let data = try await makeRequest("/user/scrobble")
            return try JSONDecoder().decode(ScrobbleLinks.self, from: data)
        } catch let err as AccountError {
            errorMessage = err.message
            return nil
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    /// Links (or relinks) a ListenBrainz user token.
    func linkListenBrainz(token: String) async -> Bool {
        guard isLoggedIn else { return false }
        struct Body: Encodable { let listenbrainz_token: String }
        do {
            _ = try await makeRequest("/user/scrobble", method: "PUT", body: Body(listenbrainz_token: token))
            return true
        } catch let err as AccountError {
            errorMessage = err.message
            return false
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    /// Enables or disables scrobbling without changing linked accounts.
    func setScrobblingEnabled(_ enabled: Bool) async -> Bool {
        guard isLoggedIn else { return false }
        struct Body: Encodable { let enabled: Bool }
        do {
            _ = try await makeRequest("/user/scrobble", method: "PUT", body: Body(enabled: enabled))
            return true
        } catch let err as AccountError {
            errorMessage = err.message
            return false
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    /// Unlinks all scrobbling accounts.
    func unlinkScrobbling() async -> Bool {
        guard isLoggedIn else { return false }
        do {
            _ = try await makeRequest("/user/scrobble", method: "DELETE")
            return true
        } catch let err as AccountError {
            errorMessage = err.message
            return false
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    /// Step 1 of the Last.fm desktop auth flow — fetch a token and the URL to open in Safari.
    func lastfmRequestToken() async -> LastfmRequestToken? {
        guard isLoggedIn else { return nil }
        do {
            let data = try await makeRequest("/user/scrobble/lastfm/request-token", method: "POST")
            return try JSONDecoder().decode(LastfmRequestToken.self, from: data)
        } catch let err as AccountError {
            errorMessage = err.message
            return nil
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    /// Step 2 — exchange an approved token for a session key. Returns the linked username on success.
    func lastfmLinkSession(token: String) async -> String? {
        guard isLoggedIn else { return nil }
        struct Body: Encodable { let token: String }
        struct Response: Decodable { let lastfm_username: String? }
        do {
            let data = try await makeRequest("/user/scrobble/lastfm/link", method: "POST", body: Body(token: token))
            return try JSONDecoder().decode(Response.self, from: data).lastfm_username
        } catch let err as AccountError {
            errorMessage = err.message
            return nil
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    /// Step 1 of the Libre.fm desktop auth flow — same protocol as Last.fm, different host.
    func librefmRequestToken() async -> LastfmRequestToken? {
        guard isLoggedIn else { return nil }
        do {
            let data = try await makeRequest("/user/scrobble/librefm/request-token", method: "POST")
            return try JSONDecoder().decode(LastfmRequestToken.self, from: data)
        } catch let err as AccountError {
            errorMessage = err.message
            return nil
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    /// Step 2 — exchange an approved Libre.fm token for a session key. Returns the linked username on success.
    func librefmLinkSession(token: String) async -> String? {
        guard isLoggedIn else { return nil }
        struct Body: Encodable { let token: String }
        struct Response: Decodable { let librefm_username: String? }
        do {
            let data = try await makeRequest("/user/scrobble/librefm/link", method: "POST", body: Body(token: token))
            return try JSONDecoder().decode(Response.self, from: data).librefm_username
        } catch let err as AccountError {
            errorMessage = err.message
            return nil
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }
}
