import Foundation

final class PersistenceService {
    static let shared = PersistenceService()

    private enum Keys {
        static let playlists = "playlists_v1"
        static let favorites = "favorites_v1"
        static let audioSettings = "audio_settings_v1"
    }

    private let defaults = UserDefaults.standard
    // JSONEncoder/JSONDecoder are not thread-safe for concurrent access, but all callers
    // of PersistenceService.shared invoke it from @MainActor context, so a single shared
    // instance per type is safe here.
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private init() {}

    func savePlaylists(_ playlists: [Playlist]) {
        if let data = try? encoder.encode(playlists) {
            defaults.set(data, forKey: Keys.playlists)
        }
    }

    func loadPlaylists() -> [Playlist] {
        guard let data = defaults.data(forKey: Keys.playlists),
              let playlists = try? decoder.decode([Playlist].self, from: data)
        else { return [] }
        return playlists
    }

    func saveFavorites(_ ids: Set<String>) {
        if let data = try? encoder.encode(Array(ids)) {
            defaults.set(data, forKey: Keys.favorites)
        }
    }

    func loadFavorites() -> Set<String> {
        guard let data = defaults.data(forKey: Keys.favorites),
              let ids = try? decoder.decode([String].self, from: data)
        else { return [] }
        return Set(ids)
    }

    func saveAudioSettings(_ settings: AudioSettings) {
        if let data = try? encoder.encode(settings) {
            defaults.set(data, forKey: Keys.audioSettings)
        }
    }

    func loadAudioSettings() -> AudioSettings? {
        guard let data = defaults.data(forKey: Keys.audioSettings),
              let settings = try? decoder.decode(AudioSettings.self, from: data)
        else { return nil }
        return settings
    }
}
