import BackgroundTasks
import Foundation

// MARK: - LumisoundTrackVaultService
//
// Drives the "reinject encrypted Lumisound metadata into every track" pipeline:
//  1. Tags newly-completed downloads immediately (`tagNewDownload`, called
//     right after a file lands on disk — see StreamingService+DownloadToLibrary).
//  2. Backfills the rest of the existing library in small batches via a
//     `BGProcessingTask` (longer-running/lower-priority than
//     `BackgroundRefreshService`'s `BGAppRefreshTask`, appropriate for a bulk
//     one-time-per-track sweep rather than a periodic check), plus an
//     in-app fallback pass so the backfill also makes progress for users who
//     rarely background the app long enough for BGProcessingTask to fire —
//     the same real-world caveat BackgroundRefreshService documents: iOS, not
//     this code, decides if/when a submitted request actually runs.
enum LumisoundTrackVaultService {
    static let taskIdentifier = "com.lumisound.ios.trackvault"

    /// Tracks in a single library scan can number in the thousands; tagging
    /// (an xattr syscall) is cheap per-file, but batching with a `Task.yield`
    /// between chunks keeps a long backfill from monopolizing the run loop.
    private static let batchSize = 40

    static func register() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: taskIdentifier, using: nil) { task in
            guard let processingTask = task as? BGProcessingTask else {
                task.setTaskCompleted(success: false)
                return
            }
            handle(task: processingTask)
        }
    }

    static func scheduleNext() {
        let request = BGProcessingTaskRequest(identifier: taskIdentifier)
        request.requiresNetworkConnectivity = false
        request.requiresExternalPower = false
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            appWarn("LumisoundTrackVaultService: submit failed: \(error.localizedDescription)", category: "background")
        }
    }

    private static func handle(task: BGProcessingTask) {
        scheduleNext()
        let work = Task {
            await runBackfill()
            task.setTaskCompleted(success: true)
        }
        task.expirationHandler = {
            work.cancel()
        }
    }

    /// Tags a single just-downloaded file immediately, so newly-downloaded
    /// tracks don't have to wait for the next backfill pass. Best-effort —
    /// failure just leaves the file for the next backfill to pick up.
    static func tagNewDownload(fileURL: URL, trackID: String, sourceURL: String) {
        guard !trackID.isEmpty else { return }
        LumisoundTrackTagger.tag(fileURL: fileURL, trackID: trackID, sourceURL: sourceURL)
    }

    /// Sweeps the local library for downloaded (non-purely-local-import)
    /// tracks that don't have the tag yet and tags them. Safe to call
    /// repeatedly/concurrently-ish since `isTagged` makes every unit of work
    /// idempotent; also called as an in-app fallback (e.g. app entering
    /// background) since BGProcessingTask timing is not guaranteed.
    @MainActor
    static func runBackfill() async {
        guard let library = LibraryManager.shared else { return }

        let candidates = library.importedSongs.filter { song in
            guard let url = song.url, let sourceTrackID = song.sourceTrackID, !sourceTrackID.isEmpty else {
                // No on-disk file, or a purely local import with no known
                // source — nothing meaningful to encrypt/reinject for these.
                return false
            }
            return !LumisoundTrackTagger.isTagged(fileURL: url)
        }
        guard !candidates.isEmpty else { return }

        let allowedIDs = loadUserRuleScript().flatMap { script in
            LumisoundTrackVaultEngine.filterSongIDs(script: script, songs: candidates, favorites: library.favoriteSongIDs)
        }

        appLog("LumisoundTrackVaultService: backfilling \(candidates.count) untagged track(s)", category: "background")

        var tagged = 0
        for (index, song) in candidates.enumerated() {
            if Task.isCancelled { break }
            if let allowedIDs, !allowedIDs.contains(song.id) { continue }
            guard let url = song.url, let sourceTrackID = song.sourceTrackID else { continue }
            // sourceTrackID is "source:id" (see Song.sourceTrackID / the
            // bridge's LUMISOUND_ID) — the source URL itself isn't stored on
            // Song today, so the sourceTrackID is what gets encrypted; a
            // future enhancement could thread the original youtubeURL
            // through from StreamTrack if a stronger guarantee is needed.
            if LumisoundTrackTagger.tag(fileURL: url, trackID: song.id, sourceURL: sourceTrackID) {
                tagged += 1
            }
            if (index + 1) % batchSize == 0 {
                await Task.yield()
            }
        }
        appLog("LumisoundTrackVaultService: tagged \(tagged)/\(candidates.count) track(s)", category: "background")
    }

    /// Optional user-authored policy script — no bundled/picker UI for this
    /// (unlike Effects/Visualizers), just an opt-in advanced override: drop a
    /// `.lua` file defining `should_tag(track)` at this path to exclude
    /// specific tracks from tagging. Absent by default, which means "tag
    /// everything" (see runBackfill's `allowedIDs` handling above).
    private static func loadUserRuleScript() -> String? {
        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("LumisoundTrackVaultRule.lua")
        return try? String(contentsOf: url, encoding: .utf8)
    }
}
