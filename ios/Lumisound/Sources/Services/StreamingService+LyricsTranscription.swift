import Foundation

// MARK: - Aria Lyrics Transcription

/// Result of `StreamingService.transcribeLyrics` — mirrors the shape
/// `/user/intelligence/lyrics-transcribe` returns.
struct LyricsTranscriptionResult {
    /// LRC-formatted text (`[mm:ss.xx]line` per line), ready to write
    /// straight to the same file `LyricsSyncEditorView`'s manual sync
    /// already writes to — see `NowPlayingView+Helpers.swift`'s
    /// `syncedLyricsURL(for:)`. Empty when `instrumental` is true.
    let lrc: String
    let instrumental: Bool
    let confidence: String
}

extension StreamingService {

    /// Has Aria Lumi listen to `song`'s own audio and produce (or, when
    /// `hintLyrics` is given, correct and re-time) synced lyrics for it —
    /// see `/user/intelligence/lyrics-transcribe` in main.py and
    /// `lyrics_ai.py` for how she actually does this (Gemini's native
    /// audio understanding, not a lyrics database lookup). This is the
    /// only lyrics source in the app that can produce anything for a
    /// user's own unreleased/personal recording, and the only one that
    /// verifies wording against the track's real audio rather than trusting
    /// fetched or imported text at face value.
    ///
    /// `hintLyrics`, when passed, should be whatever untimed text is
    /// already on hand for this track (an OVH fetch, a plain-text import) —
    /// Aria uses it as a starting point but still derives every timestamp
    /// from the audio herself and corrects any wording that doesn't match
    /// what she actually hears, so passing it both saves her work AND is
    /// the literal "cross-check this against what's playing" step.
    func transcribeLyrics(for song: Song, token: String, hintLyrics: String? = nil) async throws -> LyricsTranscriptionResult {
        guard let rawURL = song.url, rawURL.isFileURL else {
            throw StreamingError.invalidURL
        }
        // A Lumisound-locked (`.lms`) track's bytes are XOR-masked — Aria
        // (like the server's own ffprobe/loudness/artwork extraction
        // elsewhere in this app) can't listen to them directly. Upload the
        // unlocked, on-device-only view of the file instead, same as
        // `LumisoundExclusiveExtensionService.embeddedThumbnailJPEGData`
        // does for artwork.
        let uploadURL = LumisoundExclusiveExtensionService.playableURL(for: rawURL)

        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "title", value: song.title.isEmpty ? song.displayName : song.title),
            URLQueryItem(name: "artist", value: song.artistName),
        ]
        // 6000-char server-side cap (see the endpoint's `max_length`) — an
        // oversized hint is truncated rather than failing the request, so a
        // very long imported lyrics file still gets SOME cross-check value
        // out of its first few thousand characters instead of none.
        if let hintLyrics, !hintLyrics.isEmpty {
            queryItems.append(URLQueryItem(name: "hint_lyrics", value: String(hintLyrics.prefix(6000))))
        }

        var components = URLComponents()
        components.path = "/user/intelligence/lyrics-transcribe"
        components.queryItems = queryItems

        guard var request = makeRequest(components.string ?? "/user/intelligence/lyrics-transcribe") else {
            throw StreamingError.invalidURL
        }
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(uploadURL.audioMIMEType, forHTTPHeaderField: "Content-Type")
        // Transcription (a real Gemini audio-understanding call server-side)
        // takes meaningfully longer than a plain upload's own transfer time —
        // the default per-request timeout elsewhere in this app is too
        // short and would abort a genuine in-progress analysis.
        request.timeoutInterval = 120

        let (data, response) = try await StreamingService.bulkTransferSession.upload(for: request, fromFile: uploadURL)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw StreamingError.httpError((response as? HTTPURLResponse)?.statusCode ?? -1)
        }

        struct Response: Decodable { let lrc: String; let instrumental: Bool; let confidence: String }
        let decoded = try JSONDecoder().decode(Response.self, from: data)
        return LyricsTranscriptionResult(lrc: decoded.lrc, instrumental: decoded.instrumental, confidence: decoded.confidence)
    }
}

private extension URL {
    /// Best-effort audio Content-Type from the file's real extension —
    /// good enough for the server's `ffmpeg`-free Gemini upload path,
    /// which only uses this to hint the audio codec, not to validate it.
    var audioMIMEType: String {
        switch pathExtension.lowercased() {
        case "mp3":         return "audio/mpeg"
        case "m4a", "mp4":  return "audio/mp4"
        case "aac":         return "audio/aac"
        case "flac":        return "audio/flac"
        case "wav":         return "audio/wav"
        case "aiff", "aif": return "audio/aiff"
        case "ogg":         return "audio/ogg"
        case "opus":        return "audio/opus"
        default:            return "audio/mpeg"
        }
    }
}
