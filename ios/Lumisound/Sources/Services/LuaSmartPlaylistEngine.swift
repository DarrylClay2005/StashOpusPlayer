import Foundation

// MARK: - LuaSmartPlaylistEngine
//
// Runs a `SmartPlaylist.luaScript` predicate against a batch of songs in ONE
// `evaluate` call (never per-song) — every candidate song's facts are
// JSON-encoded and injected into the script, which is expected to define
// `function matches(song) ... end`; a small Lua harness (appended below the
// user's script) loops over the songs, calls `matches` under `pcall` (so one
// buggy/throwing call doesn't abort the whole batch), and returns the
// matching ids as JSON. This is the same "resolve once via JSON in/out"
// contract every other Lua feature here uses (see `LuaJSONBridge`) — no
// persistent engine, no per-item Swift<->Lua argument bridging.
enum LuaSmartPlaylistEngine {
    private struct SongFacts: Encodable {
        var id: String
        var title: String
        var artist: String
        var album: String
        var genre: String
        var year: String
        var duration: Double
        var bpm: Double?
        var favorite: Bool
        var source: String
        var playCount: Int
        var daysSincePlayed: Double?
        var daysSinceAdded: Double?
    }

    /// Returns the subset of `songs`' ids that pass `script`'s `matches`
    /// predicate, or `nil` if the script couldn't be run at all (syntax
    /// error, missing `matches` function, …) — callers should treat `nil` as
    /// "leave the existing result alone", not "nothing matched".
    @MainActor
    static func filterSongIDs(script: String, songs: [Song], favorites: Set<String>) -> Set<String>? {
        guard !songs.isEmpty else { return [] }

        let facts = songs.map { song -> SongFacts in
            SongFacts(
                id: song.id,
                title: song.title,
                artist: song.artist,
                album: song.album,
                genre: song.genre,
                year: song.year,
                duration: song.duration,
                bpm: song.bpm,
                favorite: favorites.contains(song.id),
                source: SmartPlaylist.sourceValue(of: song).rawValue,
                playCount: PlayHistoryStore.shared.playCount(for: song.id),
                daysSincePlayed: PlayHistoryStore.shared.lastPlayedAt(for: song.id).map { Date().timeIntervalSince($0) / 86400 },
                daysSinceAdded: song.dateAdded.map { Date().timeIntervalSince($0) / 86400 }
            )
        }

        let encoder = JSONEncoder()
        // snake_case keys on the Lua side, matching every other Lua-facing
        // convention in this codebase (eq_bands, pitch_semitones, …).
        encoder.keyEncodingStrategy = .convertToSnakeCase
        guard let factsData = try? encoder.encode(facts), let factsJSON = String(data: factsData, encoding: .utf8) else {
            return nil
        }

        // Quoted (not long-bracket) so a song title/artist that happens to
        // contain a long-bracket close sequence can't break out of the
        // literal and run as Lua source — see LuaJSONBridge.quotedLuaString.
        let harness = """
        local songs = json.decode(\(LuaJSONBridge.quotedLuaString(factsJSON)))
        local matched = {}
        for i = 1, #songs do
            local ok, result = pcall(matches, songs[i])
            if ok and result then
                table.insert(matched, songs[i].id)
            end
        end
        return json.encode(matched)
        """
        let source = script + "\n\n-- Auto-appended harness — see LuaSmartPlaylistEngine.\n" + harness

        do {
            let ids = try LuaJSONBridge.run(source, chunkName: "smart_playlist_rule", as: [String].self, convertFromSnakeCase: false)
            return Set(ids)
        } catch {
            appError("LuaSmartPlaylistEngine: script failed: \(error.localizedDescription)", category: "lua")
            return nil
        }
    }
}
