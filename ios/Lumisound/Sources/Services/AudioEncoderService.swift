import Foundation
import AVFoundation

// MARK: - AudioEncoderService
//
// Converts Opus / WebM / OGG files to a format AVAudioFile can open.
// Three-tier strategy, in order of preference:
//   1. Native: AVAudioFile opens the file directly (iOS 16 handles many Opus files natively)
//   2. Lossless: AVAssetReader decodes to 16-bit PCM → re-encoded as ALAC M4A
//      Identical quality to the Opus decoder's output — no generation loss.
//   3. Fallback: AVAssetExportSession → AAC M4A (for containers AVFoundation can't parse
//      natively, e.g. WebM). Opus is already lossy so the quality loss is negligible.
//
// Results are cached by file mtime + size.

final class AudioEncoderService {
    static let shared = AudioEncoderService()

    private let tempDir: URL

    private init() {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("lumisound_transcode", isDirectory: true)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        pruneOldCache()
    }

    // MARK: - Playback Transcoding

    func transcodeForPlayback(_ url: URL) async -> URL? {
        // Tier 1 — native: many formats open directly on iOS 16+
        if (try? AVAudioFile(forReading: url)) != nil { return url }

        let key    = cacheKey(for: url)
        let outURL = tempDir.appendingPathComponent("play_\(key).m4a")

        if FileManager.default.fileExists(atPath: outURL.path) {
            // A prior transcode interrupted mid-write (app killed/backgrounded) can leave a
            // truncated/corrupt .m4a behind. Without validation it would be returned as
            // "cached" forever — pruneOldCache only sweeps files >24h old, and only at the
            // next launch — permanently breaking playback for that track. Probe it first;
            // if it won't open, drop it and fall through to re-transcode.
            if (try? AVAudioFile(forReading: outURL)) != nil {
                return outURL
            }
            try? FileManager.default.removeItem(at: outURL)
        }

        // Tier 2 — lossless: decode to PCM → ALAC (identical to Opus decoder output)
        if await losslessTranscode(url, to: outURL) { return outURL }

        // Tier 3 — fallback: AAC re-encode (works for WebM and other exotic containers)
        try? FileManager.default.removeItem(at: outURL)
        return await aacExport(url, to: outURL)
    }

    // MARK: - Permanent Format Conversion (user-triggered, not playback caching)

    /// Permanently re-encodes `url` (typically an opus/webm/ogg file that
    /// only plays via the AVPlayer compatibility fallback) to AAC `.m4a` at
    /// `destinationURL`. Unlike `transcodeForPlayback`, this writes to a
    /// caller-provided permanent location rather than the pruned temp cache,
    /// and always re-encodes rather than checking for a native-open
    /// pass-through — the caller already knows this file needs converting.
    /// Tries the same AAC-export path as `transcodeForPlayback`'s tier 3
    /// first (cheapest — the source is already lossy, so there's no quality
    /// benefit to the heavier decode/re-encode tier). `AVAssetExportSession`
    /// is pickier about input containers than `AVAssetReader` though (this
    /// was previously the ONLY tier permanent conversion tried, so any file
    /// it choked on — a real-world case for some Opus-in-WebM downloads —
    /// silently stayed unconverted forever, retried every 5-minute pass with
    /// the same failure): falls back to the AVAssetReader/AVAssetWriter
    /// decode-then-AAC-encode path `transcodeForPlayback`'s tier 2 already
    /// proves works for these same containers, before giving up. Returns
    /// `true` once `destinationURL` exists and is confirmed playable.
    func convertPermanently(_ url: URL, to destinationURL: URL) async -> Bool {
        try? FileManager.default.removeItem(at: destinationURL)
        if let result = await aacExport(url, to: destinationURL),
           (try? AVAudioFile(forReading: result)) != nil {
            return true
        }
        try? FileManager.default.removeItem(at: destinationURL)
        guard await decodeAndReencode(url, to: destinationURL, settings: Self.aacSettings) else { return false }
        return (try? AVAudioFile(forReading: destinationURL)) != nil
    }

    // MARK: - Lossless decode via AVAssetReader + AVAssetWriter

    private static let alacSettings: [String: Any] = [
        AVFormatIDKey:            kAudioFormatAppleLossless,
        AVSampleRateKey:          48000.0,
        AVNumberOfChannelsKey:    2,
        AVEncoderBitDepthHintKey: 16
    ]

    private static let aacSettings: [String: Any] = [
        AVFormatIDKey:           kAudioFormatMPEG4AAC,
        AVSampleRateKey:         48000.0,
        AVNumberOfChannelsKey:   2,
        AVEncoderBitRateKey:     256_000
    ]

    private func losslessTranscode(_ url: URL, to outURL: URL) async -> Bool {
        await decodeAndReencode(url, to: outURL, settings: Self.alacSettings)
    }

    /// Decodes `url`'s audio to PCM via `AVAssetReader` and re-encodes it
    /// straight to `outURL` with `settings` via `AVAssetWriter` — the
    /// shared engine behind both the lossless (ALAC) playback-cache tier and
    /// the AAC fallback tier of `convertPermanently`. `AVAssetReader` reads
    /// container/codec combinations `AVAssetExportSession` sometimes
    /// refuses, which is the whole reason this exists as a distinct path.
    private func decodeAndReencode(_ url: URL, to outURL: URL, settings: [String: Any]) async -> Bool {
        let asset = AVURLAsset(url: url)

        guard let tracks = try? await asset.loadTracks(withMediaType: .audio),
              let track = tracks.first else { return false }

        // `.metadata` (not `.commonMetadata`) — the full set of format-
        // specific items, which is where a custom freeform atom like the
        // bridge's `LUMISOUND_ID` tag lives. AVAssetWriter does NOT copy
        // source metadata automatically; without explicitly reading and
        // re-attaching it here, every track that goes through this decode/
        // re-encode path (every WebM/Opus source AVAssetExportSession can't
        // read directly) loses its title/artist/album AND its LUMISOUND_ID
        // — silently defeating cross-device dedupe for exactly those files,
        // despite LumisoundExclusiveExtensionService's header promising
        // that tag "MUST stay plaintext/ffprobe-readable."
        let sourceMetadata = (try? await asset.load(.metadata)) ?? []

        guard let reader = try? AVAssetReader(asset: asset) else { return false }

        // Decode to 16-bit integer stereo PCM at 48 kHz (Opus native rate)
        let pcmSettings: [String: Any] = [
            AVFormatIDKey:               kAudioFormatLinearPCM,
            AVLinearPCMBitDepthKey:      16,
            AVLinearPCMIsFloatKey:       false,
            AVLinearPCMIsBigEndianKey:   false,
            AVLinearPCMIsNonInterleaved: false,
            AVSampleRateKey:             48000.0,
            AVNumberOfChannelsKey:       2
        ]
        let readerOut = AVAssetReaderTrackOutput(track: track, outputSettings: pcmSettings)
        guard reader.canAdd(readerOut) else { return false }
        reader.add(readerOut)

        guard let writer = try? AVAssetWriter(outputURL: outURL, fileType: .m4a) else { return false }
        writer.metadata = sourceMetadata
        let writerIn = AVAssetWriterInput(mediaType: .audio, outputSettings: settings)
        writerIn.expectsMediaDataInRealTime = false
        guard writer.canAdd(writerIn) else { return false }
        writer.add(writerIn)

        reader.startReading()
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)

        return await withCheckedContinuation { cont in
            writerIn.requestMediaDataWhenReady(on: .global(qos: .utility)) {
                while writerIn.isReadyForMoreMediaData {
                    if reader.status == .failed || writer.status == .failed {
                        writerIn.markAsFinished()
                        writer.cancelWriting()
                        try? FileManager.default.removeItem(at: outURL)
                        cont.resume(returning: false)
                        return
                    }
                    if let buf = readerOut.copyNextSampleBuffer() {
                        writerIn.append(buf)
                    } else {
                        writerIn.markAsFinished()
                        writer.finishWriting {
                            if writer.status != .completed {
                                try? FileManager.default.removeItem(at: outURL)
                            }
                            cont.resume(returning: writer.status == .completed)
                        }
                        return
                    }
                }
            }
        }
    }

    // MARK: - Fallback AAC export

    private func aacExport(_ url: URL, to outURL: URL) async -> URL? {
        let asset = AVURLAsset(url: url)
        guard let session = AVAssetExportSession(asset: asset,
                                                  presetName: AVAssetExportPresetAppleM4A) else {
            return nil
        }
        session.outputFileType = .m4a
        session.outputURL      = outURL
        // AVAssetExportSession does NOT carry source metadata over to the
        // output file unless explicitly told to — leaving `.metadata` unset
        // (the previous behavior here) silently strips title/artist/album
        // and, critically, the bridge's plaintext LUMISOUND_ID tag that
        // cross-device dedupe depends on. See the matching comment in
        // `decodeAndReencode`.
        session.metadata = (try? await asset.load(.metadata)) ?? []

        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            session.exportAsynchronously { cont.resume() }
        }

        guard session.status == .completed else {
            try? FileManager.default.removeItem(at: outURL)
            return nil
        }
        return outURL
    }

    // MARK: - Helpers

    private func cacheKey(for url: URL) -> String {
        let path  = url.standardizedFileURL.path
        let attrs = try? FileManager.default.attributesOfItem(atPath: path)
        let mtime = (attrs?[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
        let size  = (attrs?[.size] as? Int) ?? 0
        return "\(abs(path.hashValue))_\(Int(mtime))_\(size)"
    }

    private func pruneOldCache() {
        let fm     = FileManager.default
        let cutoff = Date().addingTimeInterval(-86400)
        guard let files = try? fm.contentsOfDirectory(
            at: tempDir, includingPropertiesForKeys: [.creationDateKey]
        ) else { return }
        for file in files where file.lastPathComponent.hasPrefix("play_") {
            if let d = try? file.resourceValues(forKeys: [.creationDateKey]).creationDate, d < cutoff {
                try? fm.removeItem(at: file)
            }
        }
    }
}
