import Foundation

/// An artist's bio/facts from GET /api/artist/bio — MusicBrainz for
/// disambiguation/basic facts, Wikipedia for the bio text and photo. Cached
/// server-side for 30 days; `found == false` means neither source matched.
struct ArtistBio: Codable {
    let found: Bool
    let name: String?
    let bio: String?
    let imageURL: String?
    let wikipediaURL: String?
    let artistType: String?
    let country: String?
    let beginDate: String?
    let endDate: String?
    let tags: [String]?

    enum CodingKeys: String, CodingKey {
        case found, name, bio
        case imageURL = "image_url"
        case wikipediaURL = "wikipedia_url"
        case artistType = "artist_type"
        case country
        case beginDate = "begin_date"
        case endDate = "end_date"
        case tags
    }
}

extension AccountService {

    // MARK: - Artist Bio

    /// Fetches an artist's bio/facts. Returns `nil` on any failure (offline,
    /// not logged in, decode error) — callers should treat that the same as
    /// "no bio available" rather than surfacing an error for what's a purely
    /// supplementary panel.
    func fetchArtistBio(name: String) async -> ArtistBio? {
        guard isLoggedIn else { return nil }
        guard let encoded = name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else { return nil }
        do {
            let data = try await makeRequest("/api/artist/bio?name=\(encoded)")
            return try JSONDecoder().decode(ArtistBio.self, from: data)
        } catch {
            return nil
        }
    }
}
