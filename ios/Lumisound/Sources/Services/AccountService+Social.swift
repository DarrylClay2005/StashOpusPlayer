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

    /// Legacy — writes the now-unused `ai_assisted_suggestions` privacy flag
    /// for backward compatibility. No UI calls this anymore: Aria Lumi runs
    /// unconditionally for every signed-in user (see `AccountView`'s "Aria
    /// Lumi" section, no longer a toggle), not gated by a per-user opt-in.
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

    /// Fetches "people who listen to what you listen to also play..."
    /// recommendations from real collaborative filtering over other opted-in
    /// users' play history — see `/social/similar-listeners` in main.py.
    /// Silent no-op on failure/empty (no history yet, no similar listeners
    /// found yet): this powers an optional Home-hub card, not worth an
    /// error banner over either way.
    func fetchSimilarListeners() async {
        guard isLoggedIn else { return }
        do {
            let data = try await makeRequest("/social/similar-listeners")
            struct Response: Decodable {
                let tracks: [TrendingTrack]
                let similarListenerCount: Int
                enum CodingKeys: String, CodingKey {
                    case tracks
                    case similarListenerCount = "similar_listener_count"
                }
            }
            let response = try JSONDecoder().decode(Response.self, from: data)
            similarListenerTracks = response.tracks
            similarListenerCount = response.similarListenerCount
        } catch {
            appWarn("fetchSimilarListeners: \(error.localizedDescription)", category: "network")
        }
    }

    /// Finds and names the single opted-in user whose top artists overlap
    /// most with the caller's own — see `/user/social/twin` in main.py for
    /// how this differs from the anonymous cohort `fetchSimilarListeners`
    /// reads from. `nil` on failure or when there isn't enough history/no
    /// match yet.
    func fetchListeningTwin() async -> ListeningTwin? {
        guard isLoggedIn else { return nil }
        do {
            let data = try await makeRequest("/user/social/twin")
            struct Response: Decodable { let twin: ListeningTwin? }
            return try JSONDecoder().decode(Response.self, from: data).twin
        } catch {
            appWarn("fetchListeningTwin: \(error.localizedDescription)", category: "network")
            return nil
        }
    }

    /// A mix seeded from the listening twin's other top artists — same
    /// seeded-yt-dlp-search shape as `fetchDiscoverMix`, just seeded from
    /// someone else's taste instead of the caller's own.
    func fetchTwinMix(limit: Int = 20) async -> [StreamTrack] {
        guard isLoggedIn else { return [] }
        do {
            let data = try await makeRequest("/user/social/twin/mix?limit=\(limit)")
            return try JSONDecoder().decode([StreamTrack].self, from: data)
        } catch {
            appWarn("fetchTwinMix: \(error.localizedDescription)", category: "network")
            return []
        }
    }
}
