import Foundation

// MARK: - Library Hub Content
//
// Query helpers backing the redesigned Library tab's "hub" landing screen
// (see `LibraryHubView`) — a dashboard of shortcuts to the user's *real*
// playlists/folders/favorites plus a few auto-generated groupings, sitting
// above the traditional Songs/Artists/Albums/... browsing tabs (still
// reachable via `LibraryTabBar`, unchanged).
//
// Everything here is a plain function, not `@Published` state — like
// `songs(byArtist:)` etc. in `LibraryManager+FavoritesAndQueries.swift`,
// callers (specifically `LibraryHubView`) are expected to snapshot these
// into local `@State` via `.task(id:)` keyed on `allSongs.count` rather than
// recomputing on every body re-evaluation, since several of these are
// O(n log n) sorts over the whole library.

extension LibraryManager {

    /// The most recently added songs, newest first. Falls back to
    /// `.distantPast` for songs with no known `dateAdded` (streamed-only
    /// entries, etc.), which sorts them to the end rather than excluding them.
    func recentlyAddedSongs(limit: Int = 25) -> [Song] {
        allSongs
            .sorted { ($0.dateAdded ?? .distantPast) > ($1.dateAdded ?? .distantPast) }
            .prefix(limit)
            .map { $0 }
    }

    /// The most-played songs (via `PlayHistoryStore`), highest count first.
    /// Songs with zero recorded plays are excluded entirely — an unplayed
    /// library shouldn't render a "Most Played" shelf full of zeros.
    func mostPlayedSongs(limit: Int = 25) -> [Song] {
        allSongs
            .map { ($0, PlayHistoryStore.shared.playCount(for: $0.id)) }
            .filter { $0.1 > 0 }
            .sorted { $0.1 > $1.1 }
            .prefix(limit)
            .map { $0.0 }
    }

    /// Favorited songs the user hasn't played in a while (or ever) — a
    /// "don't forget about these" grouping. Mirrors the rules of the
    /// auto-seeded "Forgotten Favorites" `SmartPlaylist` (see
    /// `SmartPlaylistStore.seedDefaultsIfNeeded`) but computed directly so
    /// the hub can show it even if the user deleted that smart playlist.
    func forgottenFavoriteSongs(limit: Int = 25, staleAfterDays: Double = 60) -> [Song] {
        let cutoff = Date().addingTimeInterval(-staleAfterDays * 86400)
        return favoriteSongs
            .filter { (PlayHistoryStore.shared.lastPlayedAt(for: $0.id) ?? .distantPast) < cutoff }
            .sorted {
                (PlayHistoryStore.shared.lastPlayedAt(for: $0.id) ?? .distantPast)
                    < (PlayHistoryStore.shared.lastPlayedAt(for: $1.id) ?? .distantPast)
            }
            .prefix(limit)
            .map { $0 }
    }

    /// Fraction (0...1) of `songs` that have at least one recorded play —
    /// used for the speed-dial tile's optional thin progress bar as a
    /// genuine "how much of this have you listened to" indicator rather
    /// than a decorative fake value.
    func listenedFraction(of songs: [Song]) -> Double? {
        guard !songs.isEmpty else { return nil }
        let played = songs.filter { PlayHistoryStore.shared.playCount(for: $0.id) > 0 }.count
        return Double(played) / Double(songs.count)
    }

    /// Up to 4 representative songs (with usable artwork potential) for a
    /// speed-dial tile's collage — favors songs that actually have distinct
    /// albums/artists so the 4 quadrants don't all show identical art when
    /// avoidable, but falls back to whatever's available for small
    /// playlists/folders.
    func collageSongs(from songs: [Song], limit: Int = 4) -> [Song] {
        guard songs.count > limit else { return Array(songs.prefix(limit)) }
        var seen = Set<String>()
        var picked: [Song] = []
        for song in songs {
            let key = song.groupableAlbumName
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            picked.append(song)
            if picked.count == limit { break }
        }
        if picked.count < limit {
            for song in songs where !picked.contains(where: { $0.id == song.id }) {
                picked.append(song)
                if picked.count == limit { break }
            }
        }
        return picked
    }
}
