import Foundation
import SwiftUI
import UIKit

extension AccountService {

    // MARK: - Social: listening activity & discovery

    /// Toggles whether this account's recent plays are visible to other
    /// signed-in users (title/artist only — see GET /social/activity).
    func setShareListeningActivity(_ enabled: Bool) async {
        guard isLoggedIn else { return }
        struct Body: Encodable { let share_listening_activity: Bool }
        do {
            _ = try await makeRequest("/user/privacy", method: "PUT", body: Body(share_listening_activity: enabled))
            if var user = currentUser {
                user.shareListeningActivity = enabled
                currentUser = user
                if let data = try? JSONEncoder().encode(user) {
                    UserDefaults.standard.set(data, forKey: Self.userKey)
                }
            }
        } catch let err as AccountError {
            errorMessage = err.message
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Toggles whether track titles/artists/genres may be sent to Anthropic's
    /// API to power AI-assisted metadata/EQ/duplicate/mix suggestions. Off by
    /// default — this is the first feature in the app that shares track data
    /// with a third party, so it must be an explicit opt-in.
    func setAIAssistedSuggestions(_ enabled: Bool) async {
        guard isLoggedIn else { return }
        struct Body: Encodable { let ai_assisted_suggestions: Bool }
        do {
            _ = try await makeRequest("/user/privacy", method: "PUT", body: Body(ai_assisted_suggestions: enabled))
            if var user = currentUser {
                user.aiAssistedSuggestions = enabled
                currentUser = user
                if let data = try? JSONEncoder().encode(user) {
                    UserDefaults.standard.set(data, forKey: Self.userKey)
                }
            }
        } catch let err as AccountError {
            errorMessage = err.message
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Fetches the recent "what others are listening to" feed.
    func fetchSocialActivity() async {
        guard isLoggedIn else { return }
        do {
            let data = try await makeRequest("/social/activity")
            struct Response: Decodable { let activity: [ActivityEntry] }
            socialActivity = try JSONDecoder().decode(Response.self, from: data).activity
        } catch let err as AccountError {
            errorMessage = err.message
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Fetches trending tracks aggregated across users sharing activity.
    func fetchTrendingTracks() async {
        guard isLoggedIn else { return }
        do {
            let data = try await makeRequest("/social/discover")
            struct Response: Decodable { let tracks: [TrendingTrack] }
            trendingTracks = try JSONDecoder().decode(Response.self, from: data).tracks
        } catch let err as AccountError {
            errorMessage = err.message
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
