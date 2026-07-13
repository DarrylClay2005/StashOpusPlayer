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
extension StreamingService {

    struct PendingDownloadInfo: Decodable {
        let job_id: String
        let source_track_id: String?
        let title: String?
        let artist: String?
        let media_type: String?
        let filename: String
        let created_at: String?
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
    func reconcilePendingDownloads(destinationDir: URL? = nil) async -> Int {
        let pending = await fetchPendingDownloads()
        guard !pending.isEmpty else { return 0 }

        let importDir = destinationDir ?? downloadDirectory
        try? FileManager.default.createDirectory(at: importDir, withIntermediateDirectories: true)

        var imported = 0
        for entry in pending {
            guard await importPendingDownload(entry, importDir: importDir) else { continue }
            imported += 1
        }

        if imported > 0 {
            await LibraryManager.shared?.scanLocalDocumentsAsync()
            let label = imported == 1 ? "1 download" : "\(imported) downloads"
            ToastCenter.shared.show("\(label) finished in the background", category: .download)
        }
        return imported
    }

    private func importPendingDownload(_ entry: PendingDownloadInfo, importDir: URL) async -> Bool {
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
            (downloadedURL, response) = try await URLSession.shared.download(for: request)
        } catch {
            appWarn("reconcilePendingDownloads: fetch failed for job \(entry.job_id): \(error.localizedDescription)", category: "network")
            return false
        }
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
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
        appLog("reconcilePendingDownloads: imported job \(entry.job_id) -> \(destURL.lastPathComponent)", category: "network")
        return true
    }
}
