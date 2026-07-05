import Foundation
import UIKit

extension StreamingService {

    // MARK: - Search

    func search(query: String, source: String = "youtube") async {
        guard isConfigured else {
            errorMessage = "Streaming service is unavailable right now."
            return
        }
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else {
            searchResults = []
            return
        }
        appLog("Search: \"\(query)\" [source: \(source)]", category: "network")
        isSearching = true
        isPlaylistResult = false
        errorMessage = nil
        defer { isSearching = false }

        var components = URLComponents()
        components.path = "/api/search"
        components.queryItems = [
            URLQueryItem(name: "q",      value: query),
            URLQueryItem(name: "limit",  value: "20"),
            URLQueryItem(name: "source", value: source),
        ]

        guard var request = makeRequest(components.string ?? "/api/search") else {
            errorMessage = "Invalid bridge URL."
            return
        }
        request.timeoutInterval = 20
        // Lets the bridge use this account's personally-uploaded yt-dlp
        // cookies (Settings -> YouTube Cookies) so search results include
        // age-restricted videos and aren't blocked by YouTube's
        // anonymous-request bot detection.
        if let accountToken = AccountService.shared?.token {
            request.setValue(accountToken, forHTTPHeaderField: "X-Account-Token")
        }

        do {
            let tracks = try await NetworkRetry.withRetry {
                let (data, response) = try await URLSession.shared.data(for: request)
                if let httpResponse = response as? HTTPURLResponse,
                   !(200..<300).contains(httpResponse.statusCode) {
                    throw StreamingError.httpError(httpResponse.statusCode)
                }
                return try JSONDecoder().decode([StreamTrack].self, from: data)
            }
            searchResults = tracks
            appLog("Search returned \(tracks.count) result(s) for \"\(query)\"", category: "network")
        } catch {
            appError("Search failed: \(error.localizedDescription)", category: "network")
            errorMessage = "Streaming service is unavailable right now. Please try again later."
            searchResults = []
        }
    }

    /// Autocomplete suggestions for `q` — past queries from any user, starting
    /// with `q`, most popular first. Returns `[]` on no match or any failure.
    func searchSuggestions(query: String, limit: Int = 8) async -> [SearchQueryCount] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return [] }

        var components = URLComponents()
        components.path = "/api/search/suggestions"
        components.queryItems = [
            URLQueryItem(name: "q",     value: trimmed),
            URLQueryItem(name: "limit", value: "\(limit)"),
        ]
        guard var request = makeRequest(components.string ?? "/api/search/suggestions") else { return [] }
        request.timeoutInterval = 10

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let httpResponse = response as? HTTPURLResponse,
               !(200..<300).contains(httpResponse.statusCode) {
                return []
            }
            return try JSONDecoder().decode([SearchQueryCount].self, from: data)
        } catch {
            return []
        }
    }

    /// Most popular search queries across all users in the last `days` days.
    /// Returns `[]` on no match or any failure.
    func searchTrending(limit: Int = 10, days: Int = 7) async -> [SearchQueryCount] {
        var components = URLComponents()
        components.path = "/api/search/trending"
        components.queryItems = [
            URLQueryItem(name: "limit", value: "\(limit)"),
            URLQueryItem(name: "days",  value: "\(days)"),
        ]
        guard var request = makeRequest(components.string ?? "/api/search/trending") else { return [] }
        request.timeoutInterval = 10

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let httpResponse = response as? HTTPURLResponse,
               !(200..<300).contains(httpResponse.statusCode) {
                return []
            }
            return try JSONDecoder().decode([SearchQueryCount].self, from: data)
        } catch {
            return []
        }
    }

    /// One-off lookup that finds the best streamable match for a title/artist pair
    /// without touching the published `searchResults`/`isSearching` state (which the
    /// Search tab UI is bound to). Used to resolve playable sources for tracks that
    /// arrived as metadata-only snapshots — e.g. shared/collaborative playlist tracks,
    /// which carry no stream URL by design. Returns `nil` on no match or any failure;
    /// callers should treat that as "skip this track" rather than a fatal error.
    func bestMatch(forTitle title: String, artist: String, source: String = "youtube") async -> StreamTrack? {
        guard isConfigured else { return nil }
        let query = "\(title) \(artist)".trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return nil }

        var components = URLComponents()
        components.path = "/api/search"
        components.queryItems = [
            URLQueryItem(name: "q",      value: query),
            URLQueryItem(name: "limit",  value: "1"),
            URLQueryItem(name: "source", value: source),
        ]
        guard var request = makeRequest(components.string ?? "/api/search") else { return nil }
        request.timeoutInterval = 20

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let httpResponse = response as? HTTPURLResponse,
               !(200..<300).contains(httpResponse.statusCode) {
                return nil
            }
            let tracks = try JSONDecoder().decode([StreamTrack].self, from: data)
            return tracks.first
        } catch {
            return nil
        }
    }

    /// Fetches up to `limit` tracks for a raw query without touching the published
    /// `searchResults`/`isSearching`/`errorMessage` state — see `bestMatch` above for
    /// why that matters. Used by Auto-Radio to seed several related tracks from one
    /// query without clobbering whatever the user has up in the Search tab. Returns
    /// `[]` on no results or any failure.
    func relatedTracks(query: String, source: String = "youtube", limit: Int = 5) async -> [StreamTrack] {
        guard isConfigured else { return [] }
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return [] }

        var components = URLComponents()
        components.path = "/api/search"
        components.queryItems = [
            URLQueryItem(name: "q",      value: trimmed),
            URLQueryItem(name: "limit",  value: String(limit)),
            URLQueryItem(name: "source", value: source),
        ]
        guard var request = makeRequest(components.string ?? "/api/search") else { return [] }
        request.timeoutInterval = 20

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let httpResponse = response as? HTTPURLResponse,
               !(200..<300).contains(httpResponse.statusCode) {
                return []
            }
            return try JSONDecoder().decode([StreamTrack].self, from: data)
        } catch {
            return []
        }
    }
}
