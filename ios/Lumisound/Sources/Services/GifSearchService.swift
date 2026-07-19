import Foundation

// MARK: - GifSearchResult

/// One Tenor result, as simplified by the bridge's `/api/gif-search*`
/// endpoints — a small preview for the picker grid plus the full-resolution
/// GIF URL that actually gets downloaded and uploaded if picked.
struct GifSearchResult: Decodable, Identifiable, Equatable {
    let id: String
    let description: String
    let previewURL: String?
    let gifURL: String
    let width: Int?
    let height: Int?

    enum CodingKeys: String, CodingKey {
        case id, description
        case previewURL = "preview_url"
        case gifURL     = "gif_url"
        case width, height
    }
}

private struct GifSearchResponse: Decodable {
    let results: [GifSearchResult]
}

// MARK: - GifSearchService
//
// Client for the bridge's Tenor GIF-search proxy — an alternative to picking
// an image from the photo library for avatar/banner uploads. The bridge
// holds the actual Tenor API key server-side (see `TENOR_API_KEY` in
// main.py); if it's unset there, search/trending calls 501 and this just
// returns an empty list, which the picker UI treats as "not available"
// rather than surfacing a scary error for what's an optional feature.
@MainActor
enum GifSearchService {

    static func search(query: String, limit: Int = 30) async -> [GifSearchResult] {
        guard let account = AccountService.shared,
              let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)
        else { return [] }
        return await fetch(path: "/api/gif-search?q=\(encoded)&limit=\(limit)", account: account)
    }

    static func trending(limit: Int = 30) async -> [GifSearchResult] {
        guard let account = AccountService.shared else { return [] }
        return await fetch(path: "/api/gif-search/trending?limit=\(limit)", account: account)
    }

    /// Downloads the actual GIF bytes for a picked result, ready to hand
    /// straight to `uploadAvatarData(_:)`/`uploadBannerData(_:)` — those
    /// already sniff for a GIF header themselves, so no extra tagging needed.
    static func downloadData(for result: GifSearchResult) async -> Data? {
        guard let url = URL(string: result.gifURL) else { return nil }
        guard let (data, resp) = try? await URLSession.shared.data(from: url),
              let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode)
        else { return nil }
        return data
    }

    private static func fetch(path: String, account: AccountService) async -> [GifSearchResult] {
        guard let req = account.makeBaseRequest(path, method: "GET") else { return [] }
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                // 501 = not configured server-side; anything else is a
                // transient failure. Either way, an empty result list is the
                // right UI outcome for an optional, best-effort feature.
                return []
            }
            return try JSONDecoder().decode(GifSearchResponse.self, from: data).results
        } catch {
            appWarn("GifSearchService: \(error.localizedDescription)", category: "social")
            return []
        }
    }
}
