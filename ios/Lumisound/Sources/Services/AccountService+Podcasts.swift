import Foundation

extension AccountService {

    // MARK: - Podcasts

    /// Subscribes to a podcast RSS feed — the bridge fetches+validates it
    /// once (extracting title/artwork) before persisting the subscription.
    func subscribeToPodcast(feedURL: String) async -> PodcastSubscription? {
        guard isLoggedIn else { return nil }
        struct Body: Encodable { let feed_url: String }
        do {
            let data = try await makeRequest("/user/podcasts/subscriptions", method: "POST", body: Body(feed_url: feedURL))
            return try JSONDecoder().decode(PodcastSubscription.self, from: data)
        } catch let err as AccountError {
            errorMessage = err.message
            return nil
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    func fetchPodcastSubscriptions() async -> [PodcastSubscription] {
        guard isLoggedIn else { return [] }
        do {
            let data = try await makeRequest("/user/podcasts/subscriptions")
            return try JSONDecoder().decode([PodcastSubscription].self, from: data)
        } catch {
            errorMessage = (error as? AccountError)?.message ?? error.localizedDescription
            return []
        }
    }

    func unsubscribeFromPodcast(id: String) async {
        guard isLoggedIn else { return }
        do {
            _ = try await makeRequest("/user/podcasts/subscriptions/\(id)", method: "DELETE")
        } catch {
            errorMessage = (error as? AccountError)?.message ?? error.localizedDescription
        }
    }

    /// Fetches the episode list for `feedURL` — live-parsed by the bridge on
    /// every call (no server-side episode cache; see main.py's comment on
    /// ios_podcast_subscriptions).
    func fetchPodcastEpisodes(feedURL: String) async -> [PodcastEpisode] {
        guard isLoggedIn,
              var components = URLComponents(string: "/user/podcasts/episodes") else { return [] }
        components.queryItems = [URLQueryItem(name: "feed_url", value: feedURL)]
        do {
            let data = try await makeRequest(components.string ?? "/user/podcasts/episodes")
            return try JSONDecoder().decode([PodcastEpisode].self, from: data)
        } catch {
            errorMessage = (error as? AccountError)?.message ?? error.localizedDescription
            return []
        }
    }

    /// Every tracked episode position for `feedURL`, keyed by episode guid —
    /// merge with `fetchPodcastEpisodes` results client-side to show
    /// in-progress/completed state per episode.
    func fetchPodcastEpisodeProgress(feedURL: String) async -> [String: PodcastEpisodeProgress] {
        guard isLoggedIn,
              var components = URLComponents(string: "/user/podcasts/episode-progress") else { return [:] }
        components.queryItems = [URLQueryItem(name: "feed_url", value: feedURL)]
        do {
            let data = try await makeRequest(components.string ?? "/user/podcasts/episode-progress")
            let entries = try JSONDecoder().decode([PodcastEpisodeProgress].self, from: data)
            return Dictionary(uniqueKeysWithValues: entries.map { ($0.episodeGuid, $0) })
        } catch {
            return [:]
        }
    }

    /// Fetches and parses one episode's Podcasting 2.0 chapters file
    /// (`episode.chaptersURL`, when a feed provides one). Not called
    /// automatically per-episode — only when a chapters UI is actually
    /// opened, since most episodes' chapters will never be viewed.
    func fetchPodcastChapters(url: String) async -> [PodcastChapter] {
        guard isLoggedIn,
              var components = URLComponents(string: "/user/podcasts/chapters") else { return [] }
        components.queryItems = [URLQueryItem(name: "chapters_url", value: url)]
        do {
            let data = try await makeRequest(components.string ?? "/user/podcasts/chapters")
            return try JSONDecoder().decode([PodcastChapter].self, from: data)
        } catch {
            return []
        }
    }

    /// Every in-progress (not completed, >5s in) episode across ALL
    /// subscriptions, most recently updated first — the Home hub's
    /// Continue Listening teaser's data source. `title`/`feedURL` come
    /// along on each entry so the teaser doesn't need a second fetch per
    /// feed just to show what it found (see main.py's doc comment on
    /// get_podcast_episode_progress for why `title` is a cached snapshot).
    func fetchRecentPodcastProgress(limit: Int = 10) async -> [PodcastEpisodeProgress] {
        guard isLoggedIn,
              var components = URLComponents(string: "/user/podcasts/episode-progress") else { return [] }
        components.queryItems = [URLQueryItem(name: "limit", value: "\(limit)")]
        do {
            let data = try await makeRequest(components.string ?? "/user/podcasts/episode-progress")
            return try JSONDecoder().decode([PodcastEpisodeProgress].self, from: data)
        } catch {
            return []
        }
    }

    /// Best-effort position save — called periodically by
    /// `AudioPlayerManager.pushPlaybackStateToBridge` while a podcast
    /// episode is playing. Silent on failure, same posture as the main
    /// music playback-state push it piggybacks on.
    func updatePodcastEpisodeProgress(feedURL: String, episodeGuid: String, title: String, position: Double, duration: Double, completed: Bool) async {
        guard isLoggedIn else { return }
        struct Body: Encodable {
            let feed_url: String
            let episode_guid: String
            let title: String
            let position_seconds: Double
            let duration_seconds: Double
            let completed: Bool
        }
        _ = try? await makeRequest(
            "/user/podcasts/episode-progress", method: "PUT",
            body: Body(
                feed_url: feedURL, episode_guid: episodeGuid, title: title,
                position_seconds: position, duration_seconds: duration, completed: completed
            )
        )
    }
}
