import Foundation

// MARK: - LumisoundTrackVaultEngine
//
// Optional Lua policy hook for LumisoundTrackVaultService's backfill/tagging
// pass — lets a user script opt specific tracks out of tagging (e.g. "skip
// anything in my Podcasts folder", "only tag tracks I've favorited") the same
// way SmartPlaylist rules do. Same "resolve once via JSON in/out" contract as
// LuaSmartPlaylistEngine (see that file) — no persistent engine, no per-item
// Swift<->Lua bridging, script defines `function should_tag(track) ... end`.
enum LumisoundTrackVaultEngine {
    private struct TrackFacts: Encodable {
        var id: String
        var title: String
        var artist: String
        var album: String
        var genre: String
        var source: String
        var favorite: Bool
    }

    /// Returns the subset of `songs`' ids that pass `script`'s `should_tag`
    /// predicate, or `nil` if the script couldn't be run at all — callers
    /// should treat `nil` as "tag everything" (the no-script default), not
    /// "tag nothing".
    @MainActor
    static func filterSongIDs(script: String, songs: [Song], favorites: Set<String>) -> Set<String>? {
        guard !songs.isEmpty else { return [] }

        let facts = songs.map { song in
            TrackFacts(
                id: song.id,
                title: song.title,
                artist: song.artist,
                album: song.album,
                genre: song.genre,
                source: SmartPlaylist.sourceValue(of: song).rawValue,
                favorite: favorites.contains(song.id)
            )
        }

        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        guard let factsData = try? encoder.encode(facts), let factsJSON = String(data: factsData, encoding: .utf8) else {
            return nil
        }

        // Quoted (not long-bracket) so a track title/artist that happens to
        // contain a long-bracket close sequence can't break out of the
        // literal and run as Lua source — see LuaJSONBridge.quotedLuaString.
        let harness = """
        local tracks = json.decode(\(LuaJSONBridge.quotedLuaString(factsJSON)))
        local matched = {}
        for i = 1, #tracks do
            local ok, result = pcall(should_tag, tracks[i])
            if ok and result then
                table.insert(matched, tracks[i].id)
            end
        end
        return json.encode(matched)
        """
        let source = script + "\n\n-- Auto-appended harness — see LumisoundTrackVaultEngine.\n" + harness

        do {
            let ids = try LuaJSONBridge.run(source, chunkName: "track_vault_rule", as: [String].self, convertFromSnakeCase: false)
            return Set(ids)
        } catch {
            appError("LumisoundTrackVaultEngine: script failed: \(error.localizedDescription)", category: "lua")
            return nil
        }
    }
}
