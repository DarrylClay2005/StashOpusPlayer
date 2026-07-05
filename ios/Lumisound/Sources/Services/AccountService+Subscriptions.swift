import Foundation
import SwiftUI
import UIKit

extension AccountService {

    // MARK: - Artist/Channel Subscriptions

    /// Lists the user's subscribed channels.
    func fetchSubscriptions() async -> [ArtistSubscription] {
        guard isLoggedIn else { return [] }
        do {
            let data = try await makeRequest("/user/subscriptions")
            return try JSONDecoder().decode([ArtistSubscription].self, from: data)
        } catch let err as AccountError {
            errorMessage = err.message
            return []
        } catch {
            errorMessage = error.localizedDescription
            return []
        }
    }

    /// Subscribes to a channel/artist URL (YouTube or SoundCloud).
    func addSubscription(channelUrl: String, channelName: String?) async -> Bool {
        guard isLoggedIn else { return false }
        struct Body: Encodable { let channel_url: String; let channel_name: String? }
        do {
            _ = try await makeRequest("/user/subscriptions", method: "POST", body: Body(channel_url: channelUrl, channel_name: channelName))
            return true
        } catch let err as AccountError {
            errorMessage = err.message
            return false
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    /// Unsubscribes from a channel.
    func removeSubscription(id: String) async -> Bool {
        guard isLoggedIn else { return false }
        do {
            _ = try await makeRequest("/user/subscriptions/\(id)", method: "DELETE")
            return true
        } catch let err as AccountError {
            errorMessage = err.message
            return false
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    /// Resolves a YouTube channel URL/@handle/search term to a real channel
    /// (id, title, thumbnail) via POST /youtube/resolve-channel.
    func resolveYoutubeChannel(query: String) async -> ResolvedChannel? {
        guard isLoggedIn else { return nil }
        struct Body: Encodable { let query: String }
        do {
            let data = try await makeRequest("/youtube/resolve-channel", method: "POST", body: Body(query: query))
            return try JSONDecoder().decode(ResolvedChannel.self, from: data)
        } catch let err as AccountError {
            errorMessage = err.message
            return nil
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    /// Fetches recent uploads for a resolved channel (GET /youtube/channel-uploads).
    func fetchChannelUploads(channelId: String, limit: Int = 10) async -> [StreamTrack] {
        guard isLoggedIn else { return [] }
        do {
            let data = try await makeRequest("/youtube/channel-uploads?channel_id=\(channelId)&limit=\(limit)")
            return try JSONDecoder().decode([StreamTrack].self, from: data)
        } catch let err as AccountError {
            errorMessage = err.message
            return []
        } catch {
            errorMessage = error.localizedDescription
            return []
        }
    }

    /// Checks a channel for new uploads since the last check, returning any new tracks found.
    func checkSubscription(id: String) async -> [StreamTrack] {
        guard isLoggedIn else { return [] }
        do {
            let data = try await makeRequest("/user/subscriptions/\(id)/check", method: "POST")
            return try JSONDecoder().decode(SubscriptionCheckResult.self, from: data).newTracks
        } catch let err as AccountError {
            errorMessage = err.message
            return []
        } catch {
            errorMessage = error.localizedDescription
            return []
        }
    }

    /// Checks every subscribed channel for new uploads, one after another
    /// (each check is its own request; the server creates the in-app
    /// notification for any new track, same as tapping "Check Now" per
    /// channel). Used by both the Subscriptions screen's "Check All" and
    /// `BackgroundRefreshService`'s periodic background run.
    func checkAllSubscriptions() async {
        guard isLoggedIn else { return }
        let subscriptions = await fetchSubscriptions()
        for subscription in subscriptions {
            _ = await checkSubscription(id: subscription.id)
        }
    }
}
