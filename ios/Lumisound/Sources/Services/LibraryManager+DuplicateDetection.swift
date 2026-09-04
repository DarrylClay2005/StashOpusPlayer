import Foundation
import MediaPlayer
import UIKit

extension LibraryManager {

    /// True if `allSongs` already contains a song matching `title`/`artist`
    /// (normalized — case/diacritic/punctuation-insensitive, same rules as
    /// `DuplicateFinderService`), and within `DuplicateFinderService
    /// .durationTolerance` of `duration` when one is provided. Used by
    /// "Download All" to skip tracks that already exist locally under any
    /// filename or source — including manually-imported files or ones that
    /// predate the `LUMISOUND_ID`/`sourceTrackID` tagging — so re-downloads
    /// aren't queued just because the track lacks a matching source ID.
    ///
    /// Uses `normalizeArtist` (not plain `normalize`) so this matches exactly
    /// what `DuplicateFinderService`'s own scan considers a duplicate — these
    /// used to disagree (this check used plain `normalize`), which meant a
    /// track could round-trip through a re-download here undetected and only
    /// get caught later by a manual Duplicate Scanner run.
    func isAlreadyImported(title: String, artist: String, duration: TimeInterval? = nil) -> Bool {
        let key = DuplicateFinderService.normalize(title) + "|" + DuplicateFinderService.normalizeArtist(artist)
        guard key != "|" else { return false }
        return allSongs.contains { song in
            let songKey = DuplicateFinderService.normalize(song.title) + "|" + DuplicateFinderService.normalizeArtist(song.artist)
            guard songKey == key else { return false }
            guard let duration, duration > 0 else { return true }
            return abs(song.duration - duration) <= DuplicateFinderService.durationTolerance
        }
    }

    /// A precomputed index of the library's imported tracks for O(1) duplicate
    /// checks. `isAlreadyImported` is O(library) per call (it re-normalizes every
    /// song), so calling it in a loop over a big playlist (up to 1000 results)
    /// was an O(results × library) string-crunch on the main thread — long enough
    /// to trip the iOS watchdog (which presents as a crash). Build this index
    /// ONCE, then query it per candidate in O(1).
    struct ImportedIdentityIndex {
        let byKey: [String: [TimeInterval]]
        func contains(title: String, artist: String, duration: TimeInterval?) -> Bool {
            let key = DuplicateFinderService.normalize(title) + "|" + DuplicateFinderService.normalizeArtist(artist)
            guard key != "|", let durations = byKey[key] else { return false }
            guard let duration, duration > 0 else { return true }
            return durations.contains { abs($0 - duration) <= DuplicateFinderService.durationTolerance }
        }
    }

    func importedIdentityIndex() -> ImportedIdentityIndex {
        var byKey: [String: [TimeInterval]] = [:]
        for song in allSongs {
            let key = DuplicateFinderService.normalize(song.title) + "|" + DuplicateFinderService.normalizeArtist(song.artist)
            guard key != "|" else { continue }
            byKey[key, default: []].append(song.duration)
        }
        return ImportedIdentityIndex(byKey: byKey)
    }

    /// True if a local copy of `track` already exists on the device, by EITHER:
    ///   1. an exact source-ID match (`Song.sourceTrackID` == "<source>:<id>",
    ///      i.e. the `LUMISOUND_ID` embedded at download time) whose backing file
    ///      still exists, OR
    ///   2. a normalized title+artist (+duration) match via `isAlreadyImported`,
    ///      which catches manual imports, re-encodes, and pre-tagging downloads.
    ///
    /// This is the pre-download gate for the tracked-playlist feature. Callers
    /// MUST `await scanLocalDocumentsAsync()` first so `allSongs` reflects every
    /// file in the Imported Music directory *and its subfolders* — otherwise a
    /// track that lives in a subfolder the scan hasn't seen yet would slip
    /// through and be downloaded twice (the bug this replaces: the old flow
    /// checked a stale library before yt-dlp ever ran).
    func hasLocalCopy(of track: StreamTrack) -> Bool {
        let sourceID = "\(track.source):\(track.id)"
        let fm = FileManager.default
        if allSongs.contains(where: { song in
            guard let url = song.url, fm.fileExists(atPath: url.path) else { return false }
            if song.sourceTrackID == sourceID { return true }
            // Same LumisoundTrackVault fallback as `localSourceIDs()` — only
            // consulted for songs with no plaintext sourceTrackID, so this
            // doesn't change behavior for the common already-tagged case.
            guard song.sourceTrackID == nil || song.sourceTrackID?.isEmpty == true else { return false }
            return LumisoundTrackTagger.readTag(fileURL: url)?.trackID == sourceID
        }) {
            return true
        }
        // Download-ledger check: covers tracks whose embedded LUMISOUND_ID didn't
        // round-trip (m4a dropped the tag), so the file is in the library but no
        // Song carries `sourceID`. The ledger maps sourceID → filename; if that
        // filename is still present in the library, we have it.
        if let fn = DownloadLedgerStore.shared.filename(for: sourceID),
           allSongs.contains(where: { $0.url?.lastPathComponent == fn }) {
            return true
        }
        let dur: TimeInterval? = track.durationSeconds > 0 ? TimeInterval(track.durationSeconds) : nil
        return isAlreadyImported(title: track.title, artist: track.artist, duration: dur)
    }

    /// Precomputed set of every locally-imported song's `sourceTrackID`
    /// ("source:id"), for O(1) membership checks — pairs with
    /// `importedIdentityIndex()` in `hasLocalCopy(of:localSourceIDs:identityIndex:)`.
    /// Every source ID this library already has a copy of, from EITHER the
    /// `Song.sourceTrackID` field (the plaintext `LUMISOUND_ID` container
    /// tag) or, for songs where that field is empty/missing, the
    /// LumisoundTrackVault xattr tag (see LumisoundTrackTagger) — a second,
    /// extension-agnostic signal that survives even for the container
    /// types/re-encodes where the plaintext tag doesn't round-trip. Feeds
    /// the auto-download pre-filter (`hasLocalCopy`), so recovering an
    /// identity match here directly means fewer wasted "download it again,
    /// then discover it's a duplicate" round-trips for TrackedPlaylistStore.
    func localSourceIDs() -> Set<String> {
        let presentFilenames = Set(allSongs.compactMap { song -> String? in
            guard let url = song.url, FileManager.default.fileExists(atPath: url.path) else { return nil }
            return url.lastPathComponent
        })
        var ids = Set(allSongs.compactMap { song -> String? in
            guard let url = song.url,
                  FileManager.default.fileExists(atPath: url.path)
            else { return nil }
            return song.sourceTrackID
        })
        // The ledger is authoritative for downloads whose container metadata
        // did not survive conversion. Include only entries whose file is still
        // present, so a deleted track becomes eligible again.
        ids.formUnion(DownloadLedgerStore.shared.presentSourceIDs(presentFilenames: presentFilenames))
        for song in allSongs where song.sourceTrackID == nil || song.sourceTrackID?.isEmpty == true {
            guard let url = song.url, let tag = LumisoundTrackTagger.readTag(fileURL: url) else { continue }
            ids.insert(tag.trackID)
        }
        return ids
    }

    /// O(1)-per-track variant of `hasLocalCopy(of:)` for checking MANY tracks
    /// in a loop (e.g. resolving a tracked playlist with hundreds of tracks).
    /// `hasLocalCopy(of:)` alone is O(library) per call — fine for a single
    /// check, but calling it once per track over a big playlist is the exact
    /// O(results × library) main-thread hang that trips the watchdog (see
    /// `importedIdentityIndex`'s doc comment, and `StreamSearchView
    /// .refreshDownloadedStatus` for the same fix already applied there).
    /// Build `localSourceIDs`/`identityIndex` ONCE before the loop:
    /// ```
    /// let ids = library.localSourceIDs()
    /// let index = library.importedIdentityIndex()
    /// tracks.filter { !library.hasLocalCopy(of: $0, localSourceIDs: ids, identityIndex: index) }
    /// ```
    func hasLocalCopy(of track: StreamTrack, localSourceIDs: Set<String>, identityIndex: ImportedIdentityIndex) -> Bool {
        let sourceID = "\(track.source):\(track.id)"
        if localSourceIDs.contains(sourceID) { return true }
        // Ledger fallback only applies to the rare track whose embedded
        // LUMISOUND_ID didn't round-trip — not the common path, so leaving
        // this as an O(library) lookup (like `hasLocalCopy(of:)` does) is
        // fine; it doesn't reintroduce the O(results × library) hang.
        if let fn = DownloadLedgerStore.shared.filename(for: sourceID),
           allSongs.contains(where: { $0.url?.lastPathComponent == fn }) {
            return true
        }
        let dur: TimeInterval? = track.durationSeconds > 0 ? TimeInterval(track.durationSeconds) : nil
        return identityIndex.contains(title: track.title, artist: track.artist, duration: dur)
    }
}
