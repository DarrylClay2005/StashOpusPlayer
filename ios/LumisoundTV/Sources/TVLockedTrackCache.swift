import Foundation

// MARK: - TVLockedTrackCache
//
// Downloads and unlocks a Lumisound-locked (`.lms`) Personal Cloud Library
// track to a local temp file, so `TVPlayerModel` can hand AVFoundation
// something it can actually decode — see `TVLockFormat`'s header comment for
// why the raw bytes aren't playable as-is. Full-file, not incremental
// streaming (same tradeoff the native iOS app already makes for its own
// local `.lms` files — the XOR transform needs the whole payload up front),
// so this is consistent with existing behavior elsewhere in this app family,
// not a new architectural compromise introduced here.
//
// An `actor` rather than a plain class: `playableURL(for:)` is called from
// both `loadCurrent()` and `beginCrossfade()`, which can legitimately
// overlap (a crossfade starting into the next track while the current one is
// still resolving) — the actor serializes access to `inFlight` so two
// concurrent requests for the SAME track share one download instead of
// racing two separate ones.
actor TVLockedTrackCache {
    static let shared = TVLockedTrackCache()

    private var inFlight: [String: Task<URL?, Never>] = [:]

    /// Returns a local file URL AVFoundation can actually play. For a
    /// non-locked item this is just `item.streamURL` unchanged (no I/O). For
    /// a locked item, returns a cached unlocked copy if one already exists,
    /// otherwise downloads+unlocks (joining an in-flight request for the
    /// same track id rather than starting a second one), or `nil` if the
    /// download or unlock fails.
    func playableURL(for item: TVPlayable) async -> URL? {
        guard item.isLocked else { return item.streamURL }

        if let existing = inFlight[item.id] {
            return await existing.value
        }
        let task = Task<URL?, Never> {
            await Self.downloadAndUnlock(item: item)
        }
        inFlight[item.id] = task
        let result = await task.value
        inFlight[item.id] = nil
        return result
    }

    private static func downloadAndUnlock(item: TVPlayable) async -> URL? {
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appendingPathComponent("lumisound_tv_cloud_lms_playable", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let realExt = item.ext.isEmpty ? "m4a" : item.ext
        let outURL = dir.appendingPathComponent(item.id).appendingPathExtension(realExt)
        if fm.fileExists(atPath: outURL.path) {
            return outURL
        }

        var request = URLRequest(url: item.streamURL)
        if let token = item.authToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        request.timeoutInterval = 120

        let data: Data
        do {
            let (responseData, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                tvWarn("TVLockedTrackCache: bad response fetching \(item.title)", category: "playback")
                return nil
            }
            data = responseData
        } catch {
            tvWarn("TVLockedTrackCache: download failed for \(item.title): \(error.localizedDescription)", category: "playback")
            return nil
        }

        let lockedTempURL = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("lms")
        defer { try? fm.removeItem(at: lockedTempURL) }
        do {
            try data.write(to: lockedTempURL, options: .atomic)
        } catch {
            tvWarn("TVLockedTrackCache: write failed for \(item.title): \(error.localizedDescription)", category: "playback")
            return nil
        }
        guard TVLockFormat.unlock(lockedURL: lockedTempURL, to: outURL) else {
            tvWarn("TVLockedTrackCache: unlock failed for \(item.title)", category: "playback")
            return nil
        }
        return outURL
    }
}
