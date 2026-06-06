import Foundation
import ffmpegkit

// MARK: - AudioEncoderService

/// Wraps FFmpegKit for two purposes:
///   1. Transparent playback transcoding: converts Opus/WebM/OGG → ALAC M4A so
///      AVAudioFile can open them. Results are cached by mtime+size so the same
///      file isn't re-transcoded on every play.
///   2. User-facing format conversion: converts any local song to a chosen format
///      and saves the output alongside the source file.
@MainActor
final class AudioEncoderService {
    static let shared = AudioEncoderService()

    // MARK: - Output Formats

    enum OutputFormat: String, CaseIterable, Identifiable {
        case m4aAAC  = "M4A (AAC)"
        case m4aALAC = "M4A Lossless"
        case mp3     = "MP3"
        case flac    = "FLAC"
        case wav     = "WAV"

        var id: String { rawValue }

        var fileExtension: String {
            switch self {
            case .m4aAAC, .m4aALAC: return "m4a"
            case .mp3:  return "mp3"
            case .flac: return "flac"
            case .wav:  return "wav"
            }
        }

        var systemImage: String {
            switch self {
            case .m4aAAC:  return "waveform"
            case .m4aALAC: return "hifispeaker.fill"
            case .mp3:     return "music.note"
            case .flac:    return "waveform.badge.plus"
            case .wav:     return "waveform.path"
            }
        }

        fileprivate var codecArgs: String {
            switch self {
            case .m4aAAC:  return "-c:a aac -b:a 256k"
            case .m4aALAC: return "-c:a alac"
            case .mp3:     return "-c:a libmp3lame -q:a 0"
            case .flac:    return "-c:a flac -compression_level 8"
            case .wav:     return "-c:a pcm_s24le"
            }
        }
    }

    // MARK: - Private

    private let tempDir: URL

    private init() {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("lumisound_transcode", isDirectory: true)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        pruneOldCache()
    }

    // MARK: - Playback Transcoding (internal)

    /// Converts an Opus/WebM/OGG file to an ALAC M4A temp file suitable for AVAudioFile.
    /// ALAC is lossless, so no additional quality is lost versus the original container.
    /// Cached by file mtime + size; only transcodes once per changed file.
    func transcodeForPlayback(_ url: URL) async -> URL? {
        let key = cacheKey(for: url)
        let outURL = tempDir.appendingPathComponent("play_\(key).m4a")

        if FileManager.default.fileExists(atPath: outURL.path) {
            return outURL
        }

        let cmd = buildCmd(input: url, codecArgs: "-c:a alac -map_metadata 0", output: outURL)
        return await runFFmpeg(cmd) ? outURL : nil
    }

    // MARK: - Format Conversion (user-facing)

    /// Converts a local song file to `format`, saving the result next to the source.
    /// Returns the output URL on success.
    func convert(song: Song, to format: OutputFormat) async throws -> URL {
        guard let inputURL = song.url, inputURL.isFileURL else { throw EncoderError.noURL }

        let outName = inputURL.deletingPathExtension().lastPathComponent + "." + format.fileExtension
        let outURL  = inputURL.deletingLastPathComponent().appendingPathComponent(outName)

        let cmd = buildCmd(input: inputURL, codecArgs: "\(format.codecArgs) -map_metadata 0", output: outURL)

        guard await runFFmpeg(cmd) else {
            throw EncoderError.ffmpegFailed("See device console for FFmpeg logs")
        }
        return outURL
    }

    // MARK: - Helpers

    private func buildCmd(input: URL, codecArgs: String, output: URL) -> String {
        let safeIn  = input.path.replacingOccurrences(of: "\"", with: "\\\"")
        let safeOut = output.path.replacingOccurrences(of: "\"", with: "\\\"")
        return "-y -i \"\(safeIn)\" \(codecArgs) \"\(safeOut)\""
    }

    private func runFFmpeg(_ cmd: String) async -> Bool {
        await withCheckedContinuation { cont in
            FFmpegKit.executeAsync(cmd) { session in
                guard let session else { cont.resume(returning: false); return }
                cont.resume(returning: ReturnCode.isSuccess(session.getReturnCode()))
            }
        }
    }

    private func cacheKey(for url: URL) -> String {
        let path  = url.standardizedFileURL.path
        let attrs = try? FileManager.default.attributesOfItem(atPath: path)
        let mtime = (attrs?[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
        let size  = (attrs?[.size] as? Int) ?? 0
        return "\(abs(path.hashValue))_\(Int(mtime))_\(size)"
    }

    private func pruneOldCache() {
        let fm      = FileManager.default
        let cutoff  = Date().addingTimeInterval(-86400)
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

// MARK: - Errors

enum EncoderError: LocalizedError {
    case noURL
    case ffmpegFailed(String)

    var errorDescription: String? {
        switch self {
        case .noURL:              return "Song has no local file URL"
        case .ffmpegFailed(let m): return "Conversion failed: \(m)"
        }
    }
}
