import Foundation

/// A group of tracks played on this same month/day in a previous year (see
/// GET /user/on-this-day) — reconstructed server-side directly from play
/// history rows, one group per year that has any.
struct OnThisDayGroup: Codable, Identifiable {
    let yearsAgo: Int
    let year: Int
    let tracks: [StreamTrack]

    var id: Int { year }

    enum CodingKeys: String, CodingKey {
        case yearsAgo = "years_ago"
        case year
        case tracks
    }
}

extension AccountService {

    // MARK: - On This Day

    /// Fetches this account's "On This Day" throwback — what was playing on
    /// today's month/day in previous years.
    func fetchOnThisDay() async -> [OnThisDayGroup] {
        guard isLoggedIn else { return [] }
        do {
            let data = try await makeRequest("/user/on-this-day")
            return try JSONDecoder().decode([OnThisDayGroup].self, from: data)
        } catch let err as AccountError {
            errorMessage = err.message
            return []
        } catch {
            errorMessage = error.localizedDescription
            return []
        }
    }
}
