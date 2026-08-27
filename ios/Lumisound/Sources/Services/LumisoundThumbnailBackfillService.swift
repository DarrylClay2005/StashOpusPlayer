import Foundation

// MARK: - LumisoundThumbnailBackfillService
//
// One-time (per-track) backfill of pre-uploaded thumbnails for locked
// (.lms) cloud tracks that were uploaded before artwork-upload existed —
// see `StreamingService.uploadTrack`'s thumbnail-upload step and
// `/user/music/artwork-upload` in main.py. That fix only runs DURING a
// fresh upload; a track that was already sitting in the cloud library
// before it shipped has `has_artwork = true` in its metadata row (correctly
// recording that the ORIGINAL file had embedded art) but no actual
// thumbnail bytes ever got stored server-side for it — the server can't
// extract them itself from locked bytes, same limitation as ever. Every
// track uploaded before this feature existed would otherwise show no
// artwork forever, no matter how long the app runs, since nothing else
// ever revisits an already-completed upload.
@MainActor
enum LumisoundThumbnailBackfillService {
    private static let backfilledIDsKey = "thumbnailBackfill.completedSongIDs"
    /// Caps real per-pass work (an AVAsset metadata load + a network
    /// upload per track) — this runs on the same 5-minute foreground loop
    /// as the rest of LumisoundTrackVaultService's migrations, so a
    /// several-hundred-track backlog converges over a handful of app
    /// sessions rather than trying to push it all through in one burst.
    private static let maxPerPass = 20

    private static var backfilledIDs: Set<String> {
        get { Set(UserDefaults.standard.stringArray(forKey: backfilledIDsKey) ?? []) }
        set { UserDefaults.standard.set(Array(newValue), forKey: backfilledIDsKey) }
    }

    static func runIfNeeded() async {
        guard let library = LibraryManager.shared, let streaming = StreamingService.shared,
              let account = AccountService.shared, let token = account.token, account.isLoggedIn
        else { return }

        let candidates = library.importedSongs.filter { song in
            guard let url = song.url, LumisoundExclusiveExtensionService.isConverted(url) else { return false }
            return !backfilledIDs.contains(song.id)
        }
        guard !candidates.isEmpty else { return }

        // One metadata fetch for the whole pass rather than one per track —
        // this is how a local song's already-uploaded server-side id (what
        // the artwork-upload endpoint keys on) gets resolved, matched by
        // the destination filename `uploadTrack` originally used.
        guard let cloudTracks = try? await streaming.fetchUserMusicMetadata(token: token) else { return }
        let cloudByFilename = Dictionary(cloudTracks.map { ($0.filename, $0) }, uniquingKeysWith: { first, _ in first })

        var processed = 0
        for song in candidates {
            guard processed < maxPerPass else { break }
            guard let url = song.url else { continue }

            guard let cloudTrack = cloudByFilename[url.lastPathComponent] else {
                // Not uploaded yet (or upload still in flight) — leave
                // unmarked so a future pass picks it up once it is.
                continue
            }
            processed += 1
            guard cloudTrack.hasArtwork else {
                backfilledIDs.insert(song.id)  // genuinely nothing to backfill
                continue
            }
            guard let jpeg = await LumisoundExclusiveExtensionService.embeddedThumbnailJPEGData(fileURL: url) else {
                backfilledIDs.insert(song.id)  // no local thumbnail to extract either
                continue
            }
            do {
                try await streaming.uploadArtworkThumbnail(jpeg, forMetadataID: cloudTrack.id, token: token)
                backfilledIDs.insert(song.id)
            } catch {
                appWarn("LumisoundThumbnailBackfillService: upload failed for \(url.lastPathComponent): \(error.localizedDescription)", category: "network")
                // Left unmarked — retried on the next pass.
            }
        }

        if processed > 0 {
            appLog("LumisoundThumbnailBackfillService: processed \(processed) track(s)", category: "network")
        }
    }
}
