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

        if FileManager.default.fileExists(atPath: outURL.path) { return outURL }

        // Tier 2 — lossless: decode to PCM → ALAC (identical to Opus decoder output)
        if await losslessTranscode(url, to: outURL) { return outURL }

        // Tier 3 — fallback: AAC re-encode (works for WebM and other exotic containers)
        try? FileManager.default.removeItem(at: outURL)
        return await aacExport(url, to: outURL)
    }

    // MARK: - Lossless decode via AVAssetReader + AVAssetWriter

    private func losslessTranscode(_ url: URL, to outURL: URL) async -> Bool {
        let asset = AVURLAsset(url: url)

        guard let tracks = try? await asset.loadTracks(withMediaType: .audio),
              let track = tracks.first else { return false }

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

        // Re-compress with ALAC — lossless integer compression of the PCM above
        guard let writer = try? AVAssetWriter(outputURL: outURL, fileType: .m4a) else { return false }
        let alacSettings: [String: Any] = [
            AVFormatIDKey:            kAudioFormatAppleLossless,
            AVSampleRateKey:          48000.0,
            AVNumberOfChannelsKey:    2,
            AVEncoderBitDepthHintKey: 16
        ]
        let writerIn = AVAssetWriterInput(mediaType: .audio, outputSettings: alacSettings)
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
