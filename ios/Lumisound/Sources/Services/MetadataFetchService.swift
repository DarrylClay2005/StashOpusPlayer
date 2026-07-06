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

/// Fetches song metadata from a chain of free public APIs:
///   1. iTunes Search API  (best coverage for mainstream music)
///   2. MusicBrainz        (open music encyclopedia, great for indie/classical)
///   3. Deezer Search API  (European catalogue, often fills gaps)
/// Results are cached in memory for the lifetime of the app.
actor MetadataFetchService {
    static let shared = MetadataFetchService()

    // nil-wrapped Optional means "already looked up, nothing found"
    private var cache: [String: OnlineMetadata?] = [:]

    private init() {}

    /// Looks up metadata using a chain of free APIs. Returns the first successful result.
    /// *filename*, when provided, lets an ambiguous iTunes result set be
    /// disambiguated by Aria Lumi (AI-assisted suggestions, opt-in) instead
    /// of the plain "exact match or first result" heuristic — see
    /// `fetchFromItunes`.
    func fetchMetadata(title: String, artist: String, filename: String? = nil) async -> OnlineMetadata? {
        let rawTitle  = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let rawArtist = artist.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rawTitle.isEmpty else { return nil }

        let cacheKey = "\(rawTitle)|\(rawArtist)"
        if let cached = cache[cacheKey] {
            return cached
        }

        // 1. iTunes
        if let meta = await fetchFromItunes(title: rawTitle, artist: rawArtist, filename: filename) {
            cache[cacheKey] = meta
            AppLogger.shared.log("MetadataFetch[iTunes]: \"\(rawTitle)\"", category: "network")
            return meta
        }

        // 2. MusicBrainz (rate-limited: 1 req/sec — acceptable for one-off enrichment)
        if let meta = await fetchFromMusicBrainz(title: rawTitle, artist: rawArtist) {
            cache[cacheKey] = meta
            AppLogger.shared.log("MetadataFetch[MusicBrainz]: \"\(rawTitle)\"", category: "network")
            return meta
        }

        // 3. Deezer
        if let meta = await fetchFromDeezer(title: rawTitle, artist: rawArtist) {
            cache[cacheKey] = meta
            AppLogger.shared.log("MetadataFetch[Deezer]: \"\(rawTitle)\"", category: "network")
            return meta
        }

        AppLogger.shared.warn("MetadataFetch: no results from any source for \"\(rawTitle)\"", category: "network")
        cache[cacheKey] = .some(nil)
        return nil
    }

    // MARK: - iTunes

    private func fetchFromItunes(title: String, artist: String, filename: String? = nil) async -> OnlineMetadata? {
        let query = [title, artist].filter { !$0.isEmpty }.joined(separator: " ")
        guard let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://itunes.apple.com/search?term=\(encoded)&entity=song&limit=3&country=US"),
              let (data, response) = try? await URLSession.shared.data(for: URLRequest(url: url, timeoutInterval: 10)),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let results = json["results"] as? [[String: Any]],
              !results.isEmpty
        else { return nil }

        var best = results.first(where: {
            ($0["trackName"] as? String ?? "").lowercased() == title.lowercased()
        }) ?? results[0]

        // Ambiguous case: no exact title match among multiple candidates.
        // Ask Aria Lumi (opt-in AI-assisted suggestions) to disambiguate
        // instead of blindly taking the first result; falls straight through
        // to the existing `best` above on any failure, disabled toggle, or
        // low-confidence pick.
        if results.count > 1, let filename,
           !results.contains(where: { ($0["trackName"] as? String ?? "").lowercased() == title.lowercased() }) {
            let candidates = results.map { result in
                MetadataCandidate(
                    title: result["trackName"] as? String ?? "",
                    artist: result["artistName"] as? String ?? "",
                    album: result["collectionName"] as? String,
                    year: (result["releaseDate"] as? String).map { String($0.prefix(4)) },
                    source: "itunes"
                )
            }
            if let resolution = await AccountService.shared?.resolveMetadata(filename: filename, candidates: candidates) {
                best = results[resolution.bestIndex]
                await IntelligenceSuggestionCache.shared.store(
                    filename,
                    title: candidates[resolution.bestIndex].title,
                    artist: candidates[resolution.bestIndex].artist,
                    memoryID: resolution.memoryID
                )
            }
        }

        let art100 = best["artworkUrl100"] as? String ?? ""
        let art600 = best["artworkUrl600"] as? String
            ?? art100.replacingOccurrences(of: "100x100bb", with: "600x600bb")
        return OnlineMetadata(
            trackName:  best["trackName"]       as? String,
            artistName: best["artistName"]       as? String,
            albumName:  best["collectionName"]   as? String,
            genre:      best["primaryGenreName"] as? String,
            year:       (best["releaseDate"] as? String).map { String($0.prefix(4)) },
            artworkURL: URL(string: art600)
        )
    }

    // MARK: - MusicBrainz

    private func fetchFromMusicBrainz(title: String, artist: String) async -> OnlineMetadata? {
        let query = artist.isEmpty ? "recording:\"\(title)\"" : "recording:\"\(title)\" AND artist:\"\(artist)\""
        guard let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://musicbrainz.org/ws/2/recording?query=\(encoded)&limit=3&fmt=json")
        else { return nil }

        var req = URLRequest(url: url)
        req.setValue("Lumisound/1.0 (https://github.com/HeavenlyXenusVR/Lumisound)", forHTTPHeaderField: "User-Agent")
        req.timeoutInterval = 10

        guard let (data, response) = try? await URLSession.shared.data(for: req),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let recordings = json["recordings"] as? [[String: Any]],
              !recordings.isEmpty
        else { return nil }

        let best = recordings.first(where: {
            ($0["title"] as? String ?? "").lowercased() == title.lowercased()
        }) ?? recordings[0]

        let trackName   = best["title"] as? String
        let artistName  = (best["artist-credit"] as? [[String: Any]])?.first?["name"] as? String
        let releases    = best["releases"] as? [[String: Any]]
        let albumName   = releases?.first?["title"] as? String
        let date        = releases?.first?["date"] as? String

        return OnlineMetadata(
            trackName:  trackName,
            artistName: artistName,
            albumName:  albumName,
            genre:      nil,    // MusicBrainz doesn't return genre directly in recording search
            year:       date.map { String($0.prefix(4)) },
            artworkURL: nil     // Artwork requires Cover Art Archive; skip for speed
        )
    }

    // MARK: - Deezer

    private func fetchFromDeezer(title: String, artist: String) async -> OnlineMetadata? {
        let query = [title, artist].filter { !$0.isEmpty }.joined(separator: " ")
        guard let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://api.deezer.com/search?q=\(encoded)&limit=3"),
              let (data, response) = try? await URLSession.shared.data(for: URLRequest(url: url, timeoutInterval: 10)),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let results = json["data"] as? [[String: Any]],
              !results.isEmpty
        else { return nil }

        let best = results.first(where: {
            ($0["title"] as? String ?? "").lowercased() == title.lowercased()
        }) ?? results[0]
        let album     = best["album"] as? [String: Any]
        let artist2   = best["artist"] as? [String: Any]
        let coverURL  = album?["cover_big"] as? String ?? album?["cover"] as? String

        return OnlineMetadata(
            trackName:  best["title"]    as? String,
            artistName: artist2?["name"] as? String,
            albumName:  album?["title"]  as? String,
            genre:      nil,
            year:       nil,
            artworkURL: coverURL.flatMap { URL(string: $0) }
        )
    }

    /// Convenience: enriches `song` with any fields currently missing, using a single
    /// iTunes lookup. Returns the updated Song (or the original if nothing was found).
    func enrich(song: Song) async -> Song {
        var s = song
        let meta = await fetchMetadata(title: song.title, artist: song.artist, filename: song.url?.lastPathComponent)
        guard let meta else { return s }

        if s.artist.isEmpty, let a = meta.artistName { s.artist = a }
        if s.album.isEmpty,  let a = meta.albumName  { s.album  = a }
        if s.genre.isEmpty,  let g = meta.genre      { s.genre  = g }
        if s.year.isEmpty,   let y = meta.year       { s.year   = y }

        return s
    }
}
