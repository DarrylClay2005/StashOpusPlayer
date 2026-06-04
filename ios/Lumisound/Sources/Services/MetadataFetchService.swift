import Foundation
import UIKit

// MARK: - OnlineMetadata

struct OnlineMetadata {
    let trackName: String?
    let artistName: String?
    let albumName: String?
    let genre: String?
    let year: String?
    let artworkURL: URL?
}

// MARK: - MetadataFetchService

/// Fetches song metadata and artwork from the iTunes Search API (free, no key required).
/// Results are cached in memory for the lifetime of the app to avoid redundant network calls.
actor MetadataFetchService {
    static let shared = MetadataFetchService()

    // nil-wrapped Optional means "already looked up, nothing found"
    private var cache: [String: OnlineMetadata?] = [:]

    private init() {}

    /// Looks up `title` + `artist` on the iTunes Search API.
    /// Returns nil if no match is found or the network is unavailable.
    func fetchMetadata(title: String, artist: String) async -> OnlineMetadata? {
        let rawTitle  = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let rawArtist = artist.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rawTitle.isEmpty else { return nil }

        let cacheKey = "\(rawTitle)|\(rawArtist)"
        if let cached = cache[cacheKey] {
            AppLogger.shared.log("MetadataFetch: cache \(cached != nil ? "hit" : "miss(nil)") for \"\(rawTitle)\"", category: "network")
            return cached
        }

        let query = [rawTitle, rawArtist].filter { !$0.isEmpty }.joined(separator: " ")
        guard let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://itunes.apple.com/search?term=\(encoded)&entity=song&limit=3&country=US")
        else {
            AppLogger.shared.warn("MetadataFetch: could not build URL for \"\(rawTitle)\"", category: "network")
            cache[cacheKey] = .some(nil)
            return nil
        }

        AppLogger.shared.log("MetadataFetch: querying iTunes for \"\(rawTitle)\" by \"\(rawArtist)\"", category: "network")
        guard let (data, response) = try? await URLSession.shared.data(from: url) else {
            AppLogger.shared.warn("MetadataFetch: network error for \"\(rawTitle)\"", category: "network")
            cache[cacheKey] = .some(nil)
            return nil
        }
        guard (response as? HTTPURLResponse)?.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let results = json["results"] as? [[String: Any]],
              !results.isEmpty
        else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            AppLogger.shared.warn("MetadataFetch: no results for \"\(rawTitle)\" (http \(status))", category: "network")
            cache[cacheKey] = .some(nil)
            return nil
        }

        // Pick the best matching result — prefer an exact title match.
        let best = results.first(where: { result in
            let name = (result["trackName"] as? String ?? "").lowercased()
            return name == rawTitle.lowercased()
        }) ?? results[0]

        let art100 = best["artworkUrl100"] as? String ?? ""
        let art600 = best["artworkUrl600"] as? String
            ?? art100.replacingOccurrences(of: "100x100bb", with: "600x600bb")

        let meta = OnlineMetadata(
            trackName:  best["trackName"]          as? String,
            artistName: best["artistName"]          as? String,
            albumName:  best["collectionName"]      as? String,
            genre:      best["primaryGenreName"]    as? String,
            year:       (best["releaseDate"] as? String).map { String($0.prefix(4)) },
            artworkURL: URL(string: art600)
        )

        cache[cacheKey] = meta
        AppLogger.shared.log("MetadataFetch: found \"\(meta.trackName ?? rawTitle)\" by \(meta.artistName ?? "?")", category: "network")
        return meta
    }

    /// Convenience: enriches `song` with any fields currently missing, using a single
    /// iTunes lookup. Returns the updated Song (or the original if nothing was found).
    func enrich(song: Song) async -> Song {
        var s = song
        let meta = await fetchMetadata(title: song.title, artist: song.artist)
        guard let meta else { return s }

        if s.artist.isEmpty, let a = meta.artistName { s.artist = a }
        if s.album.isEmpty,  let a = meta.albumName  { s.album  = a }
        if s.genre.isEmpty,  let g = meta.genre      { s.genre  = g }
        if s.year.isEmpty,   let y = meta.year       { s.year   = y }

        return s
    }
}
