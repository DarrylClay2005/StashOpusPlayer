import Foundation
import MediaPlayer
import UIKit

extension LibraryManager {

    // MARK: - Periodic Local Metadata Refresh

    /// Number of tracks re-read from disk per 3-minute tick. Small enough that
    /// a multi-thousand-track library only takes a few minutes per pass, but
    /// keeps each tick's work (a handful of `AVAsset` metadata loads) trivial.
    private static let metadataRefreshBatchSize = 5

    /// Call once on app launch. Every 3 minutes, re-reads the embedded tags of
    /// a small rotating batch of imported tracks directly from disk and updates
    /// the library if anything changed (e.g. the bridge re-tagged a file after
    /// a metadata re-check, or the user edited tags externally).
    ///
    /// Deliberately separate from `startPeriodicMetadataReenrichment`: that
    /// sweep only targets tracks with *missing* fields and hits online lookup
    /// services every 10 minutes. This sweep covers *all* imported tracks but
    /// only re-reads local file tags — no network calls, no artwork extraction —
    /// so it stays cheap even on a full pass.
    func startPeriodicMetadataRefresh() {
        guard metadataRefreshTimer == nil else { return }

        let interval: TimeInterval = 3 * 60
        let timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                // Skip while backgrounded — re-reading file tags is wasted work
                // when the user can't see the library (e.g. background audio
                // playback keeps the process alive). Resumes on next foreground tick.
                guard UIApplication.shared.applicationState == .active else { return }
                await self?.refreshNextMetadataBatch()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        metadataRefreshTimer = timer
    }

    /// Re-reads embedded tags for the next rotating batch of imported tracks
    /// (starting at `metadataRefreshCursor`, wrapping around the array) and
    /// updates any that changed on disk since they were last scanned.
    func refreshNextMetadataBatch() async {
        guard !isRefreshingMetadata, !importedSongs.isEmpty else { return }

        isRefreshingMetadata = true
        defer { isRefreshingMetadata = false }

        let count = min(Self.metadataRefreshBatchSize, importedSongs.count)
        var updatedCount = 0

        for offset in 0..<count {
            let index = (metadataRefreshCursor + offset) % importedSongs.count
            let song = importedSongs[index]
            guard let url = song.url, FileManager.default.fileExists(atPath: url.path) else { continue }

            guard let refreshed = await importer.refreshTags(for: url, current: song) else { continue }
            guard index < importedSongs.count, importedSongs[index].id == song.id else { continue }

            importedSongs[index] = refreshed
            updatedCount += 1

            if let stamp = ScanCacheService.fileStamp(for: url) {
                ScanCacheService.shared.store(song: refreshed, for: url, stamp: stamp)
            }
        }

        metadataRefreshCursor = (metadataRefreshCursor + count) % importedSongs.count

        guard updatedCount > 0 else { return }

        appLog("Periodic metadata refresh: updated \(updatedCount) song(s)", category: "library")
        // One event for the whole batch (never per-track — this loop already
        // covers up to metadataRefreshBatchSize tracks, and logging inside
        // it would repeat the exact per-item-in-a-loop pattern that's caused
        // main-thread hangs here before).
        RemoteLogger.log(category: "sync", event: "metadata_refresh_batch",
                          detail: ["updated": updatedCount, "batchSize": count])
        ScanCacheService.shared.persist()
        rebuildAllSongs()
    }
}
