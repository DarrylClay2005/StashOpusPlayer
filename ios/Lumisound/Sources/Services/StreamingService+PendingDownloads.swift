import Foundation

// MARK: - Pending Downloads (background-completed downloads reconciliation)
//
// The job-based /api/download flow (see StreamingService+DownloadToLibrary.swift)
// already runs entirely server-side once started — yt-dlp keeps going even if
// the app is backgrounded or killed mid-poll. What this file adds is the other
// half: recovering a finished download the app never got to fetch, because the
// bridge now durably holds it (GET /api/download/pending) instead of deleting
// it after 15 minutes. Reconciliation is called from several trigger points
// (app launch, app-foreground, each BGAppRefreshTask run, and immediately on a
// "download_ready" silent push — see AppDelegate and BackgroundRefreshService)
// so a download that finishes while the app isn't open still lands in the
// library on its own, without the user needing to notice anything.
//
// Those trigger points genuinely overlap in practice — a normal "reopen the
// app" fires BOTH the launch `.task` AND the scenePhase == .active handler
// close together, and each independently lists /api/download/pending and
// tries to fetch the same job_id. /api/download/result deletes its durable
// copy after being served once, so whichever call wins gets 200 and the
// other gets 404 — confirmed in production logs as repeated 200-then-404
// pairs for the same job_id. That race was harmless on its own (the winner
// still imports correctly) but wasteful and, combined with zero logging on
// that specific failure branch, impossible to diagnose from the field. The
// gate below collapses concurrent calls into a single in-flight fetch so
// there's only ever one claimant per reconciliation pass.
private actor PendingDownloadsReconcileGate {
    private var inFlight: Task<Int, Never>?

    func run(_ work: @escaping () async -> Int) async -> Int {
        if let inFlight {
            appLog("reconcilePendingDownloads: already in flight, joining existing call instead of racing it", category: "network")
            return await inFlight.value
        }
        let task = Task { await work() }
        inFlight = task
        let result = await task.value
        inFlight = nil
        return result
    }
}

private let pendingDownloadsReconcileGate = PendingDownloadsReconcileGate()

extension StreamingService {

    struct PendingDownloadInfo: Decodable {
        let job_id: String
        let source_track_id: String?
        let title: String?
        let artist: String?
        let media_type: String?
        let filename: String
        let created_at: String?
        /// The local subfolder this job was destined for (e.g. a tracked
        /// playlist's own destination folder), carried through from the
        /// original `/api/download` request — see `destination_folder` on
        /// `downloadToLibrary`. nil/empty means the default folder.
        let destination_folder: String?
    }

    private struct PendingDownloadsResponse: Decodable {
        let pending: [PendingDownloadInfo]
    }

    /// Lists every finished-but-unfetched download job for the current
    /// account. Empty (not throwing) if logged out or the request fails —
    /// callers treat "nothing to reconcile" and "couldn't check" the same way.
    func fetchPendingDownloads() async -> [PendingDownloadInfo] {
        guard let accountToken = AccountService.shared?.token, !accountToken.isEmpty else { return [] }
        guard var request = makeRequest("/api/download/pending") else { return [] }
        request.setValue(accountToken, forHTTPHeaderField: "X-Account-Token")
        request.timeoutInterval = 20
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return [] }
            return try JSONDecoder().decode(PendingDownloadsResponse.self, from: data).pending
        } catch {
            appWarn("fetchPendingDownloads: request failed: \(error.localizedDescription)", category: "network")
            return []
        }
    }

    /// Fetches and imports every pending (finished-but-unfetched) download for
    /// the current account, exactly like the job-based path's own finishing
    /// steps (move into place, ledger record, integrity check) — then does a
    /// single library rescan at the end. Safe to call opportunistically and
    /// often: an empty pending list is a fast no-op (one GET request), and
    /// re-running after a partial success only reprocesses what's left,
    /// since each successfully-imported job is deleted server-side as it's
    /// fetched (see /api/download/result's pending-download branch).
    @discardableResult
    func reconcilePendingDownloads() async -> Int {
        await pendingDownloadsReconcileGate.run { [self] in
            await performReconcilePendingDownloads()
        }
    }

    private func performReconcilePendingDownloads() async -> Int {
        let pending = await fetchPendingDownloads()
        appLog("reconcilePendingDownloads: \(pending.count) pending job(s) found", category: "network")
        guard !pending.isEmpty else { return 0 }

        var imported = 0
        for entry in pending {
            guard await importPendingDownload(entry) else { continue }
            imported += 1
        }

        appLog("reconcilePendingDownloads: imported \(imported)/\(pending.count) pending job(s)", category: "network")
        if imported > 0 {
            await LibraryManager.shared?.scanLocalDocumentsAsync()
            let label = imported == 1 ? "1 download" : "\(imported) downloads"
            ToastCenter.shared.show("\(label) finished in the background", category: .download)
        }
        return imported
    }

    /// Imports one pending job — used both by the batch `reconcilePendingDownloads`
    /// pass (no override, uses `entry.destination_folder` as recorded on the
    /// job) and by `PendingImportsView`'s per-row "Import Now" (passes the
    /// user's picker choice as `folderOverride` when they changed it from
    /// the pre-filled default before importing).
    @discardableResult
    func importPendingDownload(_ entry: PendingDownloadInfo, folderOverride: String? = nil) async -> Bool {
        // Resolved per entry (not once for the whole batch) — different
        // pending jobs can be destined for different tracked playlists'
        // folders. Previously this was a single `destinationDir` the caller
        // passed in, which every call site left `nil`, so a track auto-
        // downloaded from a playlist with its own folder always came back
        // into the plain default folder after a crash/close recovery.
        let resolvedFolder = folderOverride ?? entry.destination_folder
        let importDir = StreamingService.downloadDirectory(forFolderName: resolvedFolder) ?? downloadDirectory
        try? FileManager.default.createDirectory(at: importDir, withIntermediateDirectories: true)

        guard let base = makeRequest("/api/download"),
              let resultURL = jobPollURL(from: base, path: "/api/download/result", jobID: entry.job_id) else {
            return false
        }
        var request = base
        request.url = resultURL
        if let accountToken = AccountService.shared?.token {
            request.setValue(accountToken, forHTTPHeaderField: "X-Account-Token")
        }
        request.timeoutInterval = 120

        let downloadedURL: URL
        let response: URLResponse
        do {
            (downloadedURL, response) = try await StreamingService.bulkTransferSession.download(for: request)
        } catch {
            appWarn("reconcilePendingDownloads: fetch failed for job \(entry.job_id): \(error.localizedDescription)", category: "network")
            return false
        }
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            // 404 here almost always means another concurrent reconcile call
            // (or the original foreground download flow, if it was still
            // polling when the app resumed) already claimed and deleted this
            // job's durable copy first — expected under the race described
            // above, not a real failure. Anything else IS worth flagging.
            if status == 404 {
                appLog("reconcilePendingDownloads: job \(entry.job_id) already claimed elsewhere (404) — skipping", category: "network")
            } else {
                appWarn("reconcilePendingDownloads: unexpected HTTP \(status) fetching job \(entry.job_id)", category: "network")
            }
            try? FileManager.default.removeItem(at: downloadedURL)
            return false
        }

        let downloadedSize = (try? FileManager.default.attributesOfItem(atPath: downloadedURL.path))?[.size] as? Int64 ?? 0
        let expectedSize = http.expectedContentLength
        if downloadedSize <= 0 || (expectedSize > 0 && downloadedSize != expectedSize) {
            try? FileManager.default.removeItem(at: downloadedURL)
            appWarn("reconcilePendingDownloads: incomplete file for job \(entry.job_id)", category: "network")
            return false
        }

        let ext = extensionForContentType(http.value(forHTTPHeaderField: "Content-Type"))
            ?? (entry.filename as NSString).pathExtension
        let rawName = entry.title ?? (entry.filename as NSString).deletingPathExtension
        let safeName = String(
            rawName.replacingOccurrences(of: "/", with: "-")
                .replacingOccurrences(of: ":", with: "-")
                .prefix(100)
        )
        let sourceTrackID = entry.source_track_id ?? entry.job_id
        let (destURL, alreadyComplete) = resolveDownloadDestination(
            preferred: importDir.appendingPathComponent("\(safeName).\(ext)"),
            sourceTrackID: sourceTrackID
        )

        if alreadyComplete {
            try? FileManager.default.removeItem(at: downloadedURL)
        } else {
            do {
                try FileManager.default.moveItem(at: downloadedURL, to: destURL)
            } catch {
                appError("reconcilePendingDownloads: move failed for job \(entry.job_id): \(error)", category: "network")
                try? FileManager.default.removeItem(at: downloadedURL)
                return false
            }
            guard CorruptFileFinderService.isValidAudioFile(at: destURL) else {
                try? FileManager.default.removeItem(at: destURL)
                appWarn("reconcilePendingDownloads: corrupt/unreadable file for job \(entry.job_id) — discarding", category: "network")
                return false
            }
        }

        DownloadLedgerStore.shared.record(sourceTrackID: sourceTrackID, filename: destURL.lastPathComponent)
        recordRecentImport(title: rawName, artist: entry.artist, destinationFolder: resolvedFolder)
        appLog("reconcilePendingDownloads: imported job \(entry.job_id) -> \(destURL.lastPathComponent)", category: "network")
        return true
    }
}
