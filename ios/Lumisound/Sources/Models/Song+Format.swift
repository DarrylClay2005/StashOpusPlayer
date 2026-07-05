import Foundation

extension Song {
    /// Unambiguously lossless container formats, determined from the file
    /// extension alone. `.m4a` is deliberately excluded — it can hold either
    /// lossless ALAC or lossy AAC, and telling them apart requires opening
    /// the file, which isn't cheap enough to do per library row. See
    /// `AudioFormatDetails.inspect`, which does the real (file-opening)
    /// lossless check for the one-shot Now Playing format detail sheet.
    var isKnownLosslessContainer: Bool {
        guard let ext = url?.pathExtension.lowercased() else { return false }
        return ["flac", "wav", "aiff", "aif", "alac"].contains(ext)
    }

    /// True when the scanned sample rate exceeds standard CD/streaming
    /// quality (44.1kHz) — a cheap "Hi-Res" proxy using the sample rate the
    /// library scanner already populated on `sampleRate`, so it's free to
    /// compute for every row without opening any files.
    var isHiResSampleRate: Bool {
        sampleRate > 44_100
    }

    /// Short uppercase format tag for display (e.g. "FLAC", "MP3", "M4A"),
    /// or `nil` if the song has no resolvable file extension (e.g. an
    /// Apple Music library item with no local URL).
    var formatTag: String? {
        guard let ext = url?.pathExtension, !ext.isEmpty else { return nil }
        return ext.uppercased()
    }

    /// Containers `AudioPlayerManager` can only play via the AVPlayer
    /// fallback (bypassing the AVAudioEngine graph entirely) — EQ, pitch,
    /// crossfade, gapless, ReplayGain, and all the special effects don't
    /// apply to these. Mirrors the extension check in
    /// `AudioPlayerManager+Scheduling.swift`'s `scheduleCurrent`.
    var usesCompatibilityFallbackFormat: Bool {
        guard let ext = url?.pathExtension.lowercased() else { return false }
        return ["opus", "webm", "ogg"].contains(ext)
    }
}
