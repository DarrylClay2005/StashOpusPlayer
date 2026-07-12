import SwiftUI
import UniformTypeIdentifiers

extension StreamSearchView {

    // MARK: — Helpers

    /// Groups `streaming.searchResults` into per-source sections, preserving the
    /// order in which each source's first result appears (so a single-source
    /// search shows one section, and a mixed-source playlist resolve shows
    /// "YouTube" / "SoundCloud" sections in result order).
    var groupedResults: [(source: String, tracks: [StreamTrack])] {
        var order: [String] = []
        var buckets: [String: [StreamTrack]] = [:]
        for track in streaming.searchResults {
            if buckets[track.source] == nil {
                buckets[track.source] = []
                order.append(track.source)
            }
            buckets[track.source]?.append(track)
        }
        return order.map { ($0, buckets[$0] ?? []) }
    }

    /// Songs already on this device whose title/artist/album match `searchText`
    /// — shown at the top of the "My Library" tab so on-device tracks actually
    /// surface in search instead of only the server-uploaded library.
    var matchingLocalSongs: [Song] {
        guard !searchText.isEmpty else { return [] }
        let q = searchText.lowercased()
        return library.allSongs.filter {
            $0.title.lowercased().contains(q)
                || $0.artist.lowercased().contains(q)
                || $0.album.lowercased().contains(q)
        }
    }

    /// Server-recorded download history entries matching `searchText` that
    /// aren't already present on this device — surfaced as "Previously
    /// Downloaded" so the user can re-download tracks they've lost (reinstall,
    /// corruption cleanup, etc.) without re-searching from scratch.
    var matchingDownloadHistory: [DownloadHistoryTrack] {
        guard !searchText.isEmpty else { return [] }
        let localIDs = Set(library.allSongs.compactMap { $0.sourceTrackID })
        return streaming.downloadHistory.filter { !localIDs.contains($0.sourceTrackID) }
    }

    func sourceLabel(_ src: String) -> String {
        switch src {
        case "youtube":    return "YouTube"
        case "soundcloud": return "SoundCloud"
        case "server":     return "Server"
        case "my":         return "My Library"
        default:           return src.capitalized
        }
    }

    func triggerSearch() {
        failedTrackIDs.removeAll()
        appBreadcrumb("Searched \"\(searchText)\" [source: \(selectedSource)]")
        if selectedSource == "server" {
            Task { await streaming.searchServerLibrary(query: searchText) }
        } else if selectedSource == "my" {
            guard let token = account.token else { return }
            Task { await streaming.fetchUserMusic(token: token, search: searchText) }
            Task { await streaming.fetchDownloadHistory(token: token, search: searchText) }
        } else if StreamingService.isSpotifyURL(searchText) {
            Task { await streaming.resolveSpotify(url: searchText, existingSongs: library.allSongs) }
        } else if StreamingService.isPlaylistURL(searchText) {
            Task { await streaming.resolvePlaylist(url: searchText, existingSongs: library.allSongs) }
        } else {
            Task { await streaming.search(query: searchText, source: selectedSource) }
        }
    }
}
