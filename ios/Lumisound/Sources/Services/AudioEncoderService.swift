import Foundation
import AVFoundation

// MARK: - AudioEncoderService
//
// Converts Opus / WebM / OGG files to M4A so AVAudioFile can open them.
// Uses AVFoundation's AVAssetExportSession — pure Apple APIs, no binary dependencies.
// Results are cached by file mtime + size so the same file is only transcoded once.

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

    /// Returns a URL suitable for AVAudioFile.
    /// First tries to open the file natively; if AVAudioFile rejects it (e.g. Opus/WebM/OGG),
    /// exports to M4A via AVAssetExportSession and caches the result.
    func transcodeForPlayback(_ url: URL) async -> URL? {
        if (try? AVAudioFile(forReading: url)) != nil { return url }

        let key    = cacheKey(for: url)
        let outURL = tempDir.appendingPathComponent("play_\(key).m4a")

        if FileManager.default.fileExists(atPath: outURL.path) { return outURL }

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
