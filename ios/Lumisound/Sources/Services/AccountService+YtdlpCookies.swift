import Foundation
import SwiftUI
import UIKit

extension AccountService {

    // MARK: - yt-dlp cookies (per-user, for authenticated/age-restricted downloads)

    /// Fetches whether this account has yt-dlp cookies configured (status
    /// only — contents are never returned).
    func fetchYtdlpCookiesStatus() async -> YtdlpCookiesStatus? {
        guard isLoggedIn else { return nil }
        do {
            let data = try await makeRequest("/user/ytdlp-cookies")
            return try JSONDecoder().decode(YtdlpCookiesStatus.self, from: data)
        } catch let err as AccountError {
            errorMessage = err.message
            return nil
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    /// Uploads (or replaces) this account's yt-dlp cookies.txt contents
    /// (Netscape format). Used to authenticate yt-dlp as this user's YouTube
    /// session for search/stream/resolve/download — required for
    /// age-restricted videos and to avoid YouTube's anonymous-request
    /// bot-detection blocks.
    func setYtdlpCookies(_ cookiesText: String) async -> Bool {
        guard isLoggedIn else { return false }
        struct Body: Encodable { let cookies_text: String }
        do {
            _ = try await makeRequest("/user/ytdlp-cookies", method: "PUT", body: Body(cookies_text: cookiesText))
            errorMessage = nil
            return true
        } catch let err as AccountError {
            errorMessage = err.message
            return false
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    /// Removes this account's stored yt-dlp cookies.
    func deleteYtdlpCookies() async -> Bool {
        guard isLoggedIn else { return false }
        do {
            _ = try await makeRequest("/user/ytdlp-cookies", method: "DELETE")
            return true
        } catch let err as AccountError {
            errorMessage = err.message
            return false
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    /// Runs the bridge's detailed cookie validator: structural checks (are
    /// the required sign-in cookies present and unexpired, is LOGIN_INFO
    /// present for age-restricted content) followed by a real yt-dlp call to
    /// confirm YouTube actually accepts them.
    func validateYtdlpCookies() async -> YtdlpCookiesValidation? {
        guard isLoggedIn else { return nil }
        do {
            let data = try await makeRequest("/user/ytdlp-cookies/validate", method: "POST")
            return try JSONDecoder().decode(YtdlpCookiesValidation.self, from: data)
        } catch let err as AccountError {
            errorMessage = err.message
            return nil
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }
}
