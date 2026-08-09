import AVFoundation

/// On-device audio metadata embedding — used by the download-relay path
/// (`StreamingService+DownloadToLibrary.swift`) since that path fetches raw
/// CDN bytes with no server-side tagging (`ios-bridge/main.py`'s
/// `/api/download/relay` deliberately does none, unlike the job-based
/// `/api/download` flow, which still embeds tags server-side via ffmpeg).
///
/// Writes the same fields the server used to embed: title/artist/album
/// (common-keyspace items, read back by `DocumentImportService.makeSong`
/// via `commonMetadata`) and a custom `LUMISOUND_ID` tag (read back via a
/// case-insensitive substring match on the item's identifier/key — see
/// `DocumentImportService.swift`).
enum AudioTagWriter {

    /// Embeds metadata into the file at `url`, returning a NEW file at a
    /// sibling temp URL — the original, untagged file at `url` is left
    /// untouched. Returns `nil` on any failure; callers MUST treat that as
    /// "fall back to the original, untagged file" rather than an error —
    /// losing the `LUMISOUND_ID` tag only means `DownloadLedgerStore`'s
    /// existing belt-and-suspenders dedup carries the load instead of the
    /// embedded-tag detection in `DocumentImportService`.
    static func tag(
        fileAt url: URL,
        title: String?,
        artist: String?,
        album: String?,
        sourceTrackID: String
    ) async -> URL? {
        let startTime = Date()
        let outURL = url.deletingLastPathComponent()
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("m4a")

        let asset = AVURLAsset(url: url)
        guard let session = makeSession(asset: asset) else {
            appWarn("AudioTagWriter: could not create export session (passthrough and AAC presets both failed) for sourceTrackID: \(sourceTrackID)", category: "network")
            return nil
        }
        let presetUsed = session.presetName == AVAssetExportPresetPassthrough ? "passthrough" : "AAC-fallback"
        session.outputFileType = .m4a
        session.outputURL = outURL
        session.metadata = buildMetadataItems(
            title: title, artist: artist, album: album, sourceTrackID: sourceTrackID
        )

        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            session.exportAsynchronously { cont.resume() }
        }

        let elapsed = Date().timeIntervalSince(startTime)
        guard session.status == .completed else {
            appWarn("AudioTagWriter: export failed (preset: \(presetUsed), elapsed: \(String(format: "%.2f", elapsed))s, sourceTrackID: \(sourceTrackID)): \(session.error?.localizedDescription ?? "unknown error")", category: "network")
            try? FileManager.default.removeItem(at: outURL)
            return nil
        }
        // `.completed` is the export session's own status, not proof the
        // resulting file actually opens — a genuinely truncated/corrupt
        // output (the app backgrounded/memory-pressured mid-export, etc.)
        // can still report `.completed`. Verify before handing this back as
        // success, matching the same "confirm playable before trusting it"
        // rule AudioEncoderService.convertPermanently already follows —
        // every caller here goes on to either replace an existing good file
        // or import this as a brand-new one, so a false "success" is a real
        // corruption risk, not just a cosmetic one.
        guard CorruptFileFinderService.isValidAudioFile(at: outURL) else {
            appWarn("AudioTagWriter: export reported success but output is unreadable (preset: \(presetUsed), elapsed: \(String(format: "%.2f", elapsed))s, sourceTrackID: \(sourceTrackID))", category: "network")
            try? FileManager.default.removeItem(at: outURL)
            return nil
        }
        appLog("AudioTagWriter: tagged (preset: \(presetUsed), elapsed: \(String(format: "%.2f", elapsed))s, sourceTrackID: \(sourceTrackID))", category: "network")
        return outURL
    }

    /// Passthrough (stream copy, no re-encode) when available — the file is
    /// already whatever container/codec the source served, so there's no
    /// reason to spend time/quality re-encoding just to add tags. Falls back
    /// to the same AAC preset `AudioEncoderService.aacExport` already uses
    /// elsewhere in this app if passthrough isn't compatible with the asset.
    private static func makeSession(asset: AVURLAsset) -> AVAssetExportSession? {
        if let passthrough = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetPassthrough) {
            return passthrough
        }
        return AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A)
    }

    private static func buildMetadataItems(
        title: String?, artist: String?, album: String?, sourceTrackID: String
    ) -> [AVMetadataItem] {
        var items: [AVMetadataItem] = []

        func commonItem(_ identifier: AVMetadataIdentifier, _ value: String?) -> AVMutableMetadataItem? {
            guard let value, !value.isEmpty else { return nil }
            let item = AVMutableMetadataItem()
            item.identifier = identifier
            item.value = value as NSString
            return item
        }

        if let item = commonItem(.commonIdentifierTitle, title) { items.append(item) }
        if let item = commonItem(.commonIdentifierArtist, artist) { items.append(item) }
        if let item = commonItem(.commonIdentifierAlbumName, album) { items.append(item) }

        // Custom LUMISOUND_ID tag. Matches what the server-side ffmpeg pass
        // used to write (a generic mp4 "mdta" metadata atom, forced via
        // `-movflags +use_metadata_tags` — see main.py's _do_download_job
        // comment on why that flag is required for mp4 to keep custom keys).
        // .quickTimeMetadata is that same generic-atom keyspace in
        // AVFoundation; its auto-derived identifier is "mdta/LUMISOUND_ID",
        // which lowercased contains "lumisound_id" — matching the reader's
        // case-insensitive substring check exactly.
        let idItem = AVMutableMetadataItem()
        idItem.keySpace = .quickTimeMetadata
        idItem.key = "LUMISOUND_ID" as NSString
        idItem.value = sourceTrackID as NSString
        items.append(idItem)

        return items
    }
}
