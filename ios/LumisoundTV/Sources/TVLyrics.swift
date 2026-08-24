import Foundation

// MARK: - TVLyricLine / TVLrcParser
//
// Ported verbatim from ios/Lumisound/Sources/Utilities/LrcParser.swift — same
// LRC timestamp grammar (`[mm:ss]` or `[mm:ss.f]`/`[mm:ss.ff]`), same
// tenths-vs-hundredths fraction handling.

struct TVLyricLine: Identifiable, Hashable {
    let id = UUID()
    let time: TimeInterval
    let text: String
}

enum TVLrcParser {
    private static let pattern = #"\[(\d{1,2}):(\d{1,2})(?:\.(\d{1,2}))?\]"#

    static func parse(_ content: String) -> [TVLyricLine] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        var parsed: [TVLyricLine] = []

        for raw in content.split(whereSeparator: \.isNewline).map(String.init) {
            let range = NSRange(raw.startIndex..<raw.endIndex, in: raw)
            let matches = regex.matches(in: raw, range: range)
            guard !matches.isEmpty else { continue }

            let text = regex.stringByReplacingMatches(in: raw, range: range, withTemplate: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)

            for match in matches {
                guard
                    let minuteRange = Range(match.range(at: 1), in: raw),
                    let secondRange = Range(match.range(at: 2), in: raw)
                else { continue }

                let minutes = TimeInterval(String(raw[minuteRange])) ?? 0
                let seconds = TimeInterval(String(raw[secondRange])) ?? 0
                var fraction: TimeInterval = 0

                if let fractionRange = Range(match.range(at: 3), in: raw) {
                    let digits = String(raw[fractionRange])
                    let value = TimeInterval(digits) ?? 0
                    fraction = digits.count == 1 ? value / 10 : value / 100
                }

                parsed.append(TVLyricLine(time: minutes * 60 + seconds + fraction, text: text))
            }
        }

        return parsed.sorted { $0.time < $1.time }
    }
}

// MARK: - TVLyricsService
//
// Fetches lyrics directly from lrclib.net (same public API + User-Agent the
// iOS app uses — see NowPlayingView+LRCLIBFetch.swift) rather than through
// the Lumisound bridge: the bridge's own /api/lyrics is dead code the iOS
// client never actually calls (it's just a cache-then-passthrough to the
// same lrclib API, gated behind the bridge's service API key, not a user
// token) — going straight to lrclib avoids depending on that key being
// configured. Falls back to api.lyrics.ovh (plain text, unsynced) if lrclib
// has nothing.

enum TVLyricsService {
    private static let headers = ["User-Agent": "Lumisound-tvOS/1.0 (https://github.com/HeavenlyXenusVR/Lumisound)"]

    static func fetch(title: String, artist: String, duration: TimeInterval) async -> [TVLyricLine]? {
        if duration > 0, var comps = URLComponents(string: "https://lrclib.net/api/get") {
            comps.queryItems = [
                URLQueryItem(name: "track_name", value: title),
                URLQueryItem(name: "artist_name", value: artist),
                URLQueryItem(name: "duration", value: String(Int(duration.rounded()))),
            ]
            if let url = comps.url, let lines = await fetchGetResult(url: url, expectedDuration: duration) {
                return lines
            }
        }

        guard var searchComps = URLComponents(string: "https://lrclib.net/api/search") else { return await fetchPlainFallback(title: title, artist: artist) }
        searchComps.queryItems = [
            URLQueryItem(name: "track_name", value: title),
            URLQueryItem(name: "artist_name", value: artist),
        ]
        guard let url = searchComps.url else { return await fetchPlainFallback(title: title, artist: artist) }

        var req = URLRequest(url: url)
        for (key, value) in headers { req.setValue(value, forHTTPHeaderField: key) }
        req.timeoutInterval = 8

        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              (resp as? HTTPURLResponse)?.statusCode == 200,
              let results = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
              !results.isEmpty
        else { return await fetchPlainFallback(title: title, artist: artist) }

        let best: [String: Any]
        if duration > 0 {
            best = results.min {
                let d0 = ($0["duration"] as? Double) ?? .infinity
                let d1 = ($1["duration"] as? Double) ?? .infinity
                return abs(d0 - duration) < abs(d1 - duration)
            } ?? results[0]
            if let bestDuration = best["duration"] as? Double, abs(bestDuration - duration) > 10 {
                return await fetchPlainFallback(title: title, artist: artist)
            }
        } else {
            best = results[0]
        }

        if let lines = lines(from: best) { return lines }
        return await fetchPlainFallback(title: title, artist: artist)
    }

    private static func fetchGetResult(url: URL, expectedDuration: TimeInterval) async -> [TVLyricLine]? {
        var req = URLRequest(url: url)
        for (key, value) in headers { req.setValue(value, forHTTPHeaderField: key) }
        req.timeoutInterval = 8

        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              (resp as? HTTPURLResponse)?.statusCode == 200,
              let result = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }

        if expectedDuration > 0, let resultDuration = result["duration"] as? Double,
           abs(resultDuration - expectedDuration) > 10 {
            return nil
        }
        return lines(from: result)
    }

    private static func lines(from result: [String: Any]) -> [TVLyricLine]? {
        if let syncedLrc = result["syncedLyrics"] as? String, !syncedLrc.isEmpty {
            let parsed = TVLrcParser.parse(syncedLrc)
            if !parsed.isEmpty { return parsed }
        }
        if let plain = result["plainLyrics"] as? String, !plain.isEmpty {
            return plain.components(separatedBy: "\n")
                .map { TVLyricLine(time: 0, text: $0) }
                .filter { !$0.text.trimmingCharacters(in: .whitespaces).isEmpty }
        }
        return nil
    }

    /// Last resort: plain, unsynced lyrics from a second free API — only
    /// reached once lrclib has genuinely returned nothing usable.
    private static func fetchPlainFallback(title: String, artist: String) async -> [TVLyricLine]? {
        guard !title.isEmpty, !artist.isEmpty,
              let encodedArtist = artist.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let encodedTitle = title.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "https://api.lyrics.ovh/v1/\(encodedArtist)/\(encodedTitle)")
        else { return nil }

        var req = URLRequest(url: url)
        req.timeoutInterval = 8
        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              (resp as? HTTPURLResponse)?.statusCode == 200,
              let result = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let plain = result["lyrics"] as? String, !plain.isEmpty
        else { return nil }

        return plain.components(separatedBy: "\n")
            .map { TVLyricLine(time: 0, text: $0) }
            .filter { !$0.text.trimmingCharacters(in: .whitespaces).isEmpty }
    }
}
