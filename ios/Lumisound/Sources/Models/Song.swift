import Foundation
import MediaPlayer

struct Song: Identifiable, Hashable, Codable {
    let id: String
    var title: String
    var artist: String
    var album: String
    var duration: TimeInterval
    var url: URL?
    var persistentID: UInt64?
    var artworkCacheKey: String?
    var trackNumber: Int
    var year: String
    var genre: String
    var bitrate: Int
    var sampleRate: Int
    /// Stable source-derived identifier (e.g. "youtube:dQw4w9WgXcQ"), read from the
    /// `LUMISOUND_ID` metadata tag the bridge embeds in tracks downloaded via
    /// `/api/download`. Lets the duplicate finder and library recognise the same
    /// source track across re-downloads/re-imports under different filenames.
    /// `nil` for tracks without this tag (older downloads, on-device imports).
    var sourceTrackID: String?
    /// HTTP headers to include when fetching this song's URL (e.g. Authorization for user music).
    /// Not persisted across launches — tokens expire and are re-acquired on next login.
    var httpHeaders: [String: String]?

    /// Estimated tempo in beats per minute, lazily computed by `BPMAnalyzerService`
    /// and cached here so the library, "smarter" crossfade, and other tempo-aware
    /// features don't need to re-decode the file on every access. `nil` until
    /// analysis has run for this track.
    var bpm: Double?

    init(
        id: String = UUID().uuidString,
        title: String,
        artist: String = "",
        album: String = "",
        duration: TimeInterval = 0,
        url: URL? = nil,
        persistentID: UInt64? = nil,
        artworkCacheKey: String? = nil,
        trackNumber: Int = 0,
        year: String = "",
        genre: String = "",
        bitrate: Int = 0,
        sampleRate: Int = 0,
        sourceTrackID: String? = nil,
        httpHeaders: [String: String]? = nil,
        bpm: Double? = nil
    ) {
        self.id = id
        self.title = title
        self.artist = artist
        self.album = album
        self.duration = duration
        self.url = url
        self.persistentID = persistentID
        self.artworkCacheKey = artworkCacheKey
        self.trackNumber = trackNumber
        self.year = year
        self.genre = genre
        self.bitrate = bitrate
        self.sampleRate = sampleRate
        self.sourceTrackID = sourceTrackID
        self.httpHeaders = httpHeaders
        self.bpm = bpm
    }

    var displayName: String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        return url?.deletingPathExtension().lastPathComponent ?? "Unknown Title"
    }

    var artistName: String {
        artist.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Unknown Artist" : artist
    }

    var albumName: String {
        album.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Unknown Album" : album
    }

    var durationText: String {
        guard duration.isFinite, duration > 0 else { return "0:00" }
        let total = Int(duration.rounded())
        return "\(total / 60):\(String(format: "%02d", total % 60))"
    }
}

extension Song {
    init?(mediaItem: MPMediaItem) {
        guard let assetURL = mediaItem.assetURL else { return nil }
        self.init(
            id: String(mediaItem.persistentID),
            title: mediaItem.title ?? assetURL.deletingPathExtension().lastPathComponent,
            artist: mediaItem.artist ?? "",
            album: mediaItem.albumTitle ?? "",
            duration: mediaItem.playbackDuration,
            url: assetURL,
            persistentID: mediaItem.persistentID,
            artworkCacheKey: String(mediaItem.persistentID),
            trackNumber: mediaItem.albumTrackNumber,
            year: "",
            genre: mediaItem.genre ?? ""
        )
    }
}
