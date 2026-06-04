import Foundation

struct Playlist: Identifiable, Hashable, Codable {
    let id: UUID
    var name: String
    var songIDs: [Song.ID]
    var createdAt: Date

    init(id: UUID = UUID(), name: String, songIDs: [Song.ID] = [], createdAt: Date = Date()) {
        self.id = id
        self.name = name
        self.songIDs = songIDs
        self.createdAt = createdAt
    }

    var songCount: Int {
        songIDs.count
    }
}
