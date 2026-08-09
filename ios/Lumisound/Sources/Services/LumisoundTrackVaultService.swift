import BackgroundTasks
import Foundation

// MARK: - LumisoundTrackVaultService
//
// Drives the "reinject encrypted Lumisound metadata into every track, then
// re-encode it into the Lumisound-exclusive format" pipeline, for the WHOLE
// local library — downloaded tracks and plain local imports alike (widened
// 2026-08; previously local imports were skipped entirely and could never
// get re-encoded):
//  1. Tags newly-completed downloads immediately (`tagNewDownload`, called
//     right after a file lands on disk — see StreamingService+DownloadToLibrary).
//  2. Backfills the rest of the existing library — including tracks the
//     user imported locally rather than downloaded through the app — in
//     small batches via a `BGProcessingTask` (longer-running/lower-priority
//     than `BackgroundRefreshService`'s `BGAppRefreshTask`, appropriate for
//     a bulk one-time-per-track sweep rather than a periodic check), plus
//     an in-app fallback pass so the backfill also makes progress for users
//     who rarely background the app long enough for BGProcessingTask to
//     fire — the same real-world caveat BackgroundRefreshService documents:
//     iOS, not this code, decides if/when a submitted request actually runs.
//  3. Every 5 minutes in the foreground (`startFiveMinuteForegroundLoop`),
//     plus whenever the BGProcessingTask above actually gets to run, forces
//     a fresh sweep for anything tagged-but-not-yet-converted and re-encodes
//     it (`runExtensionConversionPass`) — so a track that failed to convert
//     on an earlier pass, or was just tagged by the backfill above, doesn't
//     have to wait indefinitely.
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
            await runMetadataRepairMigrationIfNeeded()
            task.setTaskCompleted(success: true)
        }
        task.expirationHandler = {
            work.cancel()
        }
    }

    /// Starts the foreground 5-minute repeating check: tag anything on disk
    /// that isn't tagged yet (`runBackfill`, covering plain local imports as
    /// well as downloads — see that method), then re-encode anything tagged
    /// but not yet converted (`runExtensionConversionPass`). Runs both every
    /// tick (not just the conversion pass) so a freshly-imported local file
    /// doesn't have to wait for the app to background before it's even
    /// eligible for conversion — previously tagging only ran on backgrounding
    /// (see LumisoundApp's scenePhase handler) while this loop only
    /// converted, so a local import's first tag could be delayed well past
    /// 5 minutes. Idempotent — safe to call from every `.onAppear`/`.task`
    /// site that might race at launch, since a second call while the loop is
    /// already running is a no-op. Call once from app launch; the loop keeps
    /// firing for as long as the process is alive (it isn't tied to
    /// scenePhase — `Task.sleep` just doesn't advance while the app is
    /// suspended, so it naturally resumes on the next tick after returning
    /// to the foreground rather than needing its own scenePhase observer).
    static func startFiveMinuteForegroundLoop() {
        guard extensionConversionLoop == nil else { return }
        extensionConversionLoop = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: extensionConversionInterval)
                guard !Task.isCancelled else { break }
                await runBackfill()
                await runExtensionConversionPass()
                await runMetadataRepairMigrationIfNeeded()
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

    /// Sweeps the ENTIRE local library — downloaded tracks and plain local
    /// imports alike — for anything that doesn't have the tag yet and tags
    /// it. Widened (2026-08) from downloaded-only: the exclusive-extension
    /// re-encode pass only ever picks up tagged tracks, so a track's local
    /// origin used to mean it would never get swept into the re-encode
    /// pipeline at all. Safe to call repeatedly/concurrently-ish since
    /// `isTagged`/`needsTagging` make every unit of work idempotent; also
    /// called as an in-app fallback (e.g. app entering background) since
    /// BGProcessingTask timing is not guaranteed.
    @MainActor
    static func runBackfill() async {
        guard let library = LibraryManager.shared else { return }

        let candidates = library.importedSongs.filter { song in
            guard let url = song.url else { return false }
            let expectedTrackID = expectedTrackID(for: song)
            // needsTagging (not isTagged) — catches both untagged files AND
            // ones carrying the wrong value from the Song.id/sourceTrackID
            // mixup bug (see LumisoundTrackTagger.needsTagging), so those
            // get silently repaired here instead of being skipped forever
            // for already "having a tag."
            return LumisoundTrackTagger.needsTagging(fileURL: url, expectedTrackID: expectedTrackID)
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
            guard let url = song.url else { continue }
            // BUG FIXED (2026-08): this used to pass `song.id` — an internal,
            // path-derived identifier like "local:Imported Music/.../track.m4a"
            // — as `trackID`, instead of `sourceTrackID` ("source:id", e.g.
            // "youtube:aqGXCQ_5WOc"), for DOWNLOADED tracks specifically.
            // Every consumer of this tag (duplicate detection's vault
            // fallback, hasLocalCopy/localSourceIDs) compares the decrypted
            // trackID against a real sourceTrackID, so the wrong value meant
            // the fallback could never match anything for those tracks.
            // `expectedTrackID(for:)` below still uses the real
            // sourceTrackID whenever one exists — it only falls back to
            // song.id for plain local imports that never had a
            // sourceTrackID to begin with, so there's no real ID for a
            // future re-download to mismatch against.
            let trackID = expectedTrackID(for: song)
            let sourceURL = trackID.hasPrefix("youtube:")
                ? "https://www.youtube.com/watch?v=\(trackID.dropFirst("youtube:".count))"
                : ""
            if LumisoundTrackTagger.tag(fileURL: url, trackID: trackID, sourceURL: sourceURL) {
                tagged += 1
            }
            if (index + 1) % batchSize == 0 {
                await Task.yield()
            }
        }
        appLog("LumisoundTrackVaultService: tagged \(tagged)/\(candidates.count) track(s)", category: "background")
    }

    /// The trackID a song's vault tag should carry: its real
    /// `sourceTrackID` when it has one (a downloaded/streamed track), or its
    /// own `id` for a plain local import with no known source — giving
    /// every on-disk track SOME expected value so the re-encode pass below
    /// can pick it up, without ever inventing a fake `source:id`-shaped
    /// value that could collide with a real one.
    private static func expectedTrackID(for song: Song) -> String {
        if let sourceTrackID = song.sourceTrackID, !sourceTrackID.isEmpty {
            return sourceTrackID
        }
        return song.id
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

    /// One-time repair for tracks converted by the pre-fix version of
    /// `AudioEncoderService`, which re-encoded audio without carrying
    /// title/artist/album/`LUMISOUND_ID` metadata forward — every track
    /// converted before that fix shipped is stuck permanently "converted"
    /// (so `runExtensionConversionPass` above will never look at it again)
    /// but with a stripped, tag-less file on disk. Runs once per install
    /// (`_metadataRepairMigrationKey` guard, same shape as any other
    /// one-time migration), scanning every already-converted track and
    /// re-embedding what's missing via
    /// `LibraryManager.repairEmbeddedMetadata`. Checking
    /// `hasEmbeddedSourceTag` is an async AVAsset metadata load per file —
    /// not free — which is exactly why this is gated to run once rather
    /// than every 5-minute pass like the rest of this pipeline.
    private static let metadataRepairMigrationKey = "lumisoundTrackVault.metadataRepairMigration.v1.done"

    @MainActor
    static func runMetadataRepairMigrationIfNeeded() async {
        guard !UserDefaults.standard.bool(forKey: metadataRepairMigrationKey) else { return }
        guard let library = LibraryManager.shared else { return }
        let currentlyPlayingID = AudioPlayerManager.shared?.currentSong?.id

        let convertedURLsByID: [String: URL] = library.importedSongs.reduce(into: [:]) { acc, song in
            guard let url = song.url, LumisoundExclusiveExtensionService.isConverted(url) else { return }
            acc[song.id] = url
        }
        guard !convertedURLsByID.isEmpty else {
            UserDefaults.standard.set(true, forKey: metadataRepairMigrationKey)
            return
        }

        appLog("LumisoundTrackVaultService: metadata repair migration — checking \(convertedURLsByID.count) already-converted track(s)", category: "background")

        // Check phase: `hasEmbeddedSourceTag` for every already-converted
        // track, run concurrently off the main actor — after this fix, the
        // overwhelming majority of a library will already have its tag
        // (only tracks converted before this migration shipped don't), so
        // this scan itself is the expensive part and must not run as a
        // sequential main-actor loop (that's exactly the pattern that made
        // this migration a lag source when it was first written).
        let idsNeedingRepair: [String] = await Task.detached(priority: .utility) {
            await withTaskGroup(of: String?.self) { group in
                var needsRepair: [String] = []
                var pending = 0
                let maxConcurrent = 8
                var iterator = convertedURLsByID.makeIterator()

                func launchNext() {
                    guard let (id, url) = iterator.next() else { return }
                    pending += 1
                    group.addTask {
                        await LumisoundExclusiveExtensionService.hasEmbeddedSourceTag(fileURL: url) ? nil : id
                    }
                }
                while pending < maxConcurrent { launchNext() }
                for await result in group {
                    pending -= 1
                    if let result { needsRepair.append(result) }
                    launchNext()
                }
                return needsRepair
            }
        }.value

        guard !idsNeedingRepair.isEmpty else {
            appLog("LumisoundTrackVaultService: metadata repair migration — nothing to repair", category: "background")
            UserDefaults.standard.set(true, forKey: metadataRepairMigrationKey)
            return
        }
        appLog("LumisoundTrackVaultService: metadata repair migration — \(idsNeedingRepair.count) track(s) need repair", category: "background")

        // Repair phase: comparatively rare (only tracks actually missing
        // the tag) and each repair is a real file write, so this part stays
        // sequential on the main actor like every other mutating pass in
        // this pipeline — but it's operating on a small subset now, not the
        // whole library.
        var repaired = 0
        var allResolved = true
        for (index, id) in idsNeedingRepair.enumerated() {
            if Task.isCancelled { allResolved = false; break }
            if id == currentlyPlayingID {
                allResolved = false
                continue
            }
            if await library.repairEmbeddedMetadata(songID: id, currentlyPlayingID: currentlyPlayingID) {
                repaired += 1
            } else {
                allResolved = false
            }
            if (index + 1) % batchSize == 0 {
                await Task.yield()
            }
        }

        appLog("LumisoundTrackVaultService: metadata repair migration — repaired \(repaired)/\(idsNeedingRepair.count) track(s)", category: "background")
        // Only marked done once every converted track either already had
        // its tag or was successfully repaired this pass — anything left
        // unresolved (currently playing, or a repair that failed) means
        // this stays unset so a later pass retries it. hasEmbeddedSourceTag
        // makes re-running cheap: already-fixed tracks are skipped instantly.
        if allResolved {
            UserDefaults.standard.set(true, forKey: metadataRepairMigrationKey)
        }
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
