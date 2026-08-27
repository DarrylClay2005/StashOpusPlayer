import Foundation

extension AccountService {

    /// Fetches contextual station suggestions. The bridge combines the
    /// optional current-track seed with weighted recent plays, favorites,
    /// library genres, and time of day.
    func fetchStationSuggestions(
        seed: StationSeed? = nil,
        limit: Int = 4,
        trackLimit: Int = 6
    ) async -> [StationSuggestion] {
        guard isLoggedIn else { return [] }
        let body = seed ?? StationSeed()
        do {
            let data = try await makeRequest(
                "/user/stations/suggestions?limit=\(limit)&track_limit=\(trackLimit)",
                method: "POST",
                body: body
            )
            return try JSONDecoder().decode([StationSuggestion].self, from: data)
        } catch {
            appWarn("fetchStationSuggestions: \(error.localizedDescription)", category: "network")
            return []
        }
    }

    /// Builds one station from the current listening context for Auto-Radio.
    /// An empty result is a normal fallback: the caller keeps playback
    /// stopped rather than surfacing an error for a recommendation miss.
    func fetchAutomaticStation(
        seed: StationSeed,
        trackLimit: Int = 8
    ) async -> StationSuggestion? {
        guard isLoggedIn else { return nil }
        do {
            let data = try await makeRequest(
                "/user/stations/auto?track_limit=\(trackLimit)",
                method: "POST",
                body: seed
            )
            let station = try JSONDecoder().decode(StationSuggestion.self, from: data)
            return station.tracks.isEmpty ? nil : station
        } catch {
            appWarn("fetchAutomaticStation: \(error.localizedDescription)", category: "network")
            return nil
        }
    }
}
