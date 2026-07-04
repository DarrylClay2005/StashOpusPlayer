import Foundation

/// A portable snapshot of playlist structure + favorites, exported/imported
/// entirely on-device (no server/account involved) for backing up or moving
/// between devices. Deliberately does NOT include actual audio files —
/// Apple Music library items can't be exported as raw files at all, and even
/// imported/downloaded files would need their own transfer mechanism, so
/// this covers the part that's actually portable: the playlist/favorite
/// *structure*. `songIDs` that don't exist on the destination device are
/// skipped on import rather than failing the whole restore.
struct LibraryBackup: Codable {
    var exportedAt: Date
    var appVersion: String
    var playlists: [Playlist]
    var favoriteSongIDs: [String]

    init(playlists: [Playlist], favoriteSongIDs: Set<String>) {
        self.exportedAt = Date()
        self.appVersion = DeviceInfo.appVersion
        self.playlists = playlists
        self.favoriteSongIDs = Array(favoriteSongIDs)
    }
}
