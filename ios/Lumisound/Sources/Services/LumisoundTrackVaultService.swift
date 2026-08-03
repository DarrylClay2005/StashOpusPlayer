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

    /// How often the extension-conversion pass runs while the app is in the
    /// foreground. iOS gives no way to guarantee an exact background
    /// cadence — BGProcessingTask's `earliestBeginDate` is only a floor, not
    /// a promise (see `scheduleNext`'s doc comment) — so a genuine 5-minute
    /// check is only achievable while the app is actually open; this loop is
    /// the primary driver, with the BGProcessingTask backfill (§ below)
    /// picking up the same work opportunistically whenever iOS actually
    /// runs it in the background.
    private static let extensionConversionInterval: UInt64 = 5 * 60 * 1_000_000_000
    private static var extensionConversionLoop: Task<Void, Never>?

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
            await runExtensionConversionPass()
            task.setTaskCompleted(success: true)
        }
        task.expirationHandler = {
            work.cancel()
        }
    }

    /// Starts the foreground 5-minute repeating extension-conversion check.
    /// Idempotent — safe to call from every `.onAppear`/`.task` site that
    /// might race at launch, since a second call while the loop is already
    /// running is a no-op. Call once from app launch; the loop keeps firing
    /// for as long as the process is alive (it isn't tied to scenePhase —
    /// `Task.sleep` just doesn't advance while the app is suspended, so it
    /// naturally resumes on the next tick after returning to the
    /// foreground rather than needing its own scenePhase observer).
    static func startFiveMinuteForegroundLoop() {
        guard extensionConversionLoop == nil else { return }
        extensionConversionLoop = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: extensionConversionInterval)
                guard !Task.isCancelled else { break }
                await runExtensionConversionPass()
            }
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
            // needsTagging (not isTagged) — catches both untagged files AND
            // ones carrying the wrong value from the Song.id/sourceTrackID
            // mixup bug (see LumisoundTrackTagger.needsTagging), so those
            // get silently repaired here instead of being skipped forever
            // for already "having a tag."
            return LumisoundTrackTagger.needsTagging(fileURL: url, expectedTrackID: sourceTrackID)
        }
        guard !candidates.isEmpty else { return }

        let allowedIDs = loadUserRuleScript().flatMap { script in
            LumisoundTrackVaultEngine.filterSongIDs(script: script, songs: candidates, favorites: library.favoriteSongIDs)
        }

        appLog("LumisoundTrackVaultService: backfilling \(candidates.count) untagged/mistagged track(s)", category: "background")

        var tagged = 0
        for (index, song) in candidates.enumerated() {
            if Task.isCancelled { break }
            if let allowedIDs, !allowedIDs.contains(song.id) { continue }
            guard let url = song.url, let sourceTrackID = song.sourceTrackID else { continue }
            // BUG FIXED (2026-08): this used to pass `song.id` — an internal,
            // path-derived identifier like "local:Imported Music/.../track.m4a"
            // — as `trackID`, instead of `sourceTrackID` ("source:id", e.g.
            // "youtube:aqGXCQ_5WOc"). Every consumer of this tag (duplicate
            // detection's vault fallback, hasLocalCopy/localSourceIDs) compares
            // the decrypted trackID against a real sourceTrackID, so the wrong
            // value meant the fallback could never match anything — silently
            // defeating the whole point of tagging tracks whose sourceTrackID
            // field itself is empty (the well-known m4a LUMISOUND_ID-embedding
            // gap — see DownloadLedgerStore's doc comment), which is exactly
            // the set of tracks that actually needed this fallback to work.
            // Reconstruct a real watch URL for youtube-sourced tracks (the
            // only source we can deterministically rebuild one for from just
            // the video ID); other sources have no equivalent today, so this
            // stays empty for them — that only affects the informational
            // sourceURL field, not trackID, which is the one dedup relies on.
            let sourceURL = sourceTrackID.hasPrefix("youtube:")
                ? "https://www.youtube.com/watch?v=\(sourceTrackID.dropFirst("youtube:".count))"
                : ""
            if LumisoundTrackTagger.tag(fileURL: url, trackID: sourceTrackID, sourceURL: sourceURL) {
                tagged += 1
            }
            if (index + 1) % batchSize == 0 {
                await Task.yield()
            }
        }
        appLog("LumisoundTrackVaultService: tagged \(tagged)/\(candidates.count) track(s)", category: "background")
    }

    /// Re-encodes every vault-tagged track that isn't already converted into
    /// the Lumisound-exclusive AAC container (see
    /// `LumisoundExclusiveExtensionService`), re-keying favorites/playlists/
    /// play-history as it goes (see
    /// `LibraryManager.convertToLumisoundExclusiveExtension`). Runs on the
    /// same 5-minute foreground loop as the rest of this pipeline, plus
    /// whenever the BGProcessingTask backfill above actually gets to run.
    /// Only tagged tracks are eligible, so this always runs strictly after
    /// tagging has had a chance to catch up — a just-downloaded track gets
    /// tagged immediately (`tagNewDownload`) but its extension conversion
    /// waits for the next pass, same as backfilled-tag tracks do.
    @MainActor
    static func runExtensionConversionPass() async {
        guard let library = LibraryManager.shared else { return }
        let currentlyPlayingID = AudioPlayerManager.shared?.currentSong?.id

        // Logged unconditionally (not just on success) — this pass previously
        // logged nothing at all when it converted zero tracks, which made a
        // real bug (candidates always empty, or every conversion silently
        // failing) indistinguishable from "nothing to do yet" in the field.
        // Broken out by extension AND by tagged-vs-converted specifically —
        // "0 tagged-not-converted" is ambiguous on its own (could mean
        // "already all converted" OR "never got tagged in the first place",
        // e.g. if only one container format's downloads were actually
        // reaching tagNewDownload) — this makes that distinguishable.
        var extBreakdown: [String: (total: Int, tagged: Int, converted: Int)] = [:]
        for song in library.importedSongs {
            guard let url = song.url else { continue }
            let ext = LumisoundExclusiveExtensionService.effectiveExtension(for: url)
            var entry = extBreakdown[ext] ?? (0, 0, 0)
            entry.total += 1
            if LumisoundExclusiveExtensionService.isConverted(url) {
                entry.converted += 1
            } else if LumisoundTrackTagger.isTagged(fileURL: url) {
                entry.tagged += 1
            }
            extBreakdown[ext] = entry
        }
        let breakdownText = extBreakdown.sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value.total)tot/\($0.value.tagged)tagged-not-converted/\($0.value.converted)converted" }
            .joined(separator: ", ")
        appLog("LumisoundTrackVaultService: conversion pass — \(library.importedSongs.count) imported [\(breakdownText)], currentlyPlaying=\(currentlyPlayingID ?? "nil")", category: "background")

        let candidates = library.importedSongs.filter { song in
            guard let url = song.url else { return false }
            return !LumisoundExclusiveExtensionService.isConverted(url) && LumisoundTrackTagger.isTagged(fileURL: url)
        }
        guard !candidates.isEmpty else { return }

        var converted = 0
        var failedSongIDs: [String] = []
        for (index, song) in candidates.enumerated() {
            if Task.isCancelled { break }
            if await library.convertToLumisoundExclusiveExtension(songID: song.id, currentlyPlayingID: currentlyPlayingID) {
                converted += 1
            } else if failedSongIDs.count < 5 {
                failedSongIDs.append(song.id)
            }
            if (index + 1) % batchSize == 0 {
                await Task.yield()
            }
        }
        appLog("LumisoundTrackVaultService: converted \(converted)/\(candidates.count) track(s) to the Lumisound-exclusive extension" + (failedSongIDs.isEmpty ? "" : "; sample failures: \(failedSongIDs)"), category: "background")
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
