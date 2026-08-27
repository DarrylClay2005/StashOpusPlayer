import Foundation

/// The small set of contextual signals sent when Lumisound builds a station.
/// The bridge combines these with server-side listening history and favorites.
struct StationSeed: Codable, Hashable {
    let title: String?
    let artist: String?
    let album: String?
    let genre: String?
    let bpm: Double?
    let sourceTrackID: String?
    let localHour: Int?

    init(
        title: String? = nil,
        artist: String? = nil,
        album: String? = nil,
        genre: String? = nil,
        bpm: Double? = nil,
        sourceTrackID: String? = nil,
        localHour: Int? = Calendar.current.component(.hour, from: Date())
    ) {
        self.title = title
        self.artist = artist
        self.album = album
        self.genre = genre
        self.bpm = bpm
        self.sourceTrackID = sourceTrackID
        self.localHour = localHour
    }

    init(song: Song, bpm: Double? = nil) {
        self.init(
            title: song.title,
            artist: song.artist,
            album: song.album,
            genre: song.genre,
            bpm: bpm ?? song.bpm,
            sourceTrackID: song.sourceTrackID
        )
    }

    enum CodingKeys: String, CodingKey {
        case title, artist, album, genre, bpm
        case sourceTrackID = "source_track_id"
        case localHour = "local_hour"
    }
}

/// A playable station assembled from real search results. Stations are
/// intentionally ephemeral: starting one simply loads its tracks into the
/// existing queue, so no new playlist/storage lifecycle is needed.
struct StationSuggestion: Identifiable, Codable, Hashable {
    let id: String
    let title: String
    let subtitle: String?
    let icon: String
    let tracks: [StreamTrack]
}
