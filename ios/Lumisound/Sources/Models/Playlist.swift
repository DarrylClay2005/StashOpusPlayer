import Foundation

struct Playlist: Identifiable, Hashable, Codable {
    let id: UUID
    var name: String
    var songIDs: [Song.ID]
    var createdAt: Date
    /// Optional folder name for organizing playlists into groups. `nil`/empty means "no folder".
    var folder: String?
    /// Free-form tags for filtering/labeling playlists.
    var tags: [String]

    init(id: UUID = UUID(), name: String, songIDs: [Song.ID] = [], createdAt: Date = Date(), folder: String? = nil, tags: [String] = []) {
        self.id = id
        self.name = name
        self.songIDs = songIDs
        self.createdAt = createdAt
        self.folder = folder
        self.tags = tags
    }

    var songCount: Int {
        songIDs.count
    }

    enum CodingKeys: String, CodingKey {
        case id, name, songIDs, createdAt, folder, tags
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        songIDs = try container.decode([Song.ID].self, forKey: .songIDs)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        folder = try container.decodeIfPresent(String.self, forKey: .folder)
        tags = try container.decodeIfPresent([String].self, forKey: .tags) ?? []
    }
}
