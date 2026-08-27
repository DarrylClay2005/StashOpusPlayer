import AVFoundation
import Foundation

/// On-demand (file-opening) audio format inspection for the currently
/// playing track — deliberately NOT computed per library row (see
/// `Song.isKnownLosslessContainer`'s doc comment for why), only when the
/// user taps into the Now Playing format detail sheet.
struct AudioFormatDetails: Equatable {
    var container: String
    var isLossless: Bool
    var sampleRateHz: Double?
    var bitDepth: Int?
    var channelCount: Int?
    var bitrateKbps: Int?
    var fileSizeBytes: Int64?
    var isPlayingViaCompatibilityFallback: Bool

    /// Hi-Res Lossless requires both a lossless source and more than CD
    /// resolution. This is intentionally derived from the inspected file
    /// rather than the filename, because M4A may contain either AAC or ALAC.
    var isHiResLossless: Bool {
        isLossless && ((sampleRateHz ?? 0) > 44_100 || (bitDepth ?? 0) > 16)
    }

    var qualityLabel: String {
        if isHiResLossless { return "Hi-Res Lossless" }
        return isLossless ? "Lossless" : "Lossy"
    }

    var sampleRateText: String? {
        guard let sampleRateHz else { return nil }
        return String(format: "%.1f kHz", sampleRateHz / 1000)
    }

    var fileSizeText: String? {
        guard let fileSizeBytes else { return nil }
        return ByteCountFormatter.string(fromByteCount: fileSizeBytes, countStyle: .file)
    }

    /// Opens the file (if local) to read its real sample rate/channel count/
    /// bit depth — best-effort, synchronous. Callers should invoke this from
    /// a `.task` rather than inline in `body`, so it runs off the render pass.
    static func inspect(song: Song?, isUsingFallback: Bool) -> AudioFormatDetails? {
        guard let song else { return nil }
        var container = song.formatTag ?? "Unknown"
        var isLossless = song.isKnownLosslessContainer
        var sampleRateHz: Double? = song.sampleRate > 0 ? Double(song.sampleRate) : nil
        var bitDepth: Int?
        var channelCount: Int?
        var fileSizeBytes: Int64?

        if let url = song.url, url.isFileURL {
            if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
               let size = attrs[.size] as? Int64 {
                fileSizeBytes = size
            }
            if let file = try? AVAudioFile(forReading: LumisoundExclusiveExtensionService.playableURL(for: url)) {
                let format = file.processingFormat
                sampleRateHz = format.sampleRate
                channelCount = Int(format.channelCount)
                let sourceFormatID = file.fileFormat.streamDescription?.pointee.mFormatID
                let sourceIsLossless = isLossless ||
                    sourceFormatID == kAudioFormatAppleLossless ||
                    sourceFormatID == kAudioFormatLinearPCM
                // Prefer the container's declared bits-per-channel. The
                // processing format is often Float32 even when the source is
                // a 16-bit ALAC file.
                if sourceIsLossless, let streamDescription = file.fileFormat.streamDescription {
                    let declaredBits = Int(streamDescription.pointee.mBitsPerChannel)
                    bitDepth = declaredBits > 0 ? declaredBits : nil
                }
                if sourceIsLossless, bitDepth == nil {
                    switch format.commonFormat {
                    case .pcmFormatInt16: bitDepth = 16
                    case .pcmFormatInt32, .pcmFormatFloat32: bitDepth = 32
                    case .pcmFormatFloat64: bitDepth = 64
                    default: bitDepth = nil
                    }
                }
                // ".m4a" is ambiguous from the extension alone (ALAC or AAC) —
                // now that the file is actually open, resolve it for real.
                if container == "M4A" || container == "LMS M4A" {
                    isLossless = sourceFormatID == kAudioFormatAppleLossless
                }
            }
        }

        let bitrateKbps: Int? = song.bitrate > 0 ? song.bitrate / 1000 : nil

        if container == "Unknown", song.persistentID != nil {
            container = "Apple Music"
        }

        return AudioFormatDetails(
            container: container,
            isLossless: isLossless,
            sampleRateHz: sampleRateHz,
            bitDepth: bitDepth,
            channelCount: channelCount,
            bitrateKbps: bitrateKbps,
            fileSizeBytes: fileSizeBytes,
            isPlayingViaCompatibilityFallback: isUsingFallback
        )
    }
}
