import Foundation

final class PersistenceService {
    static let shared = PersistenceService()

    private enum Keys {
        static let playlists = "playlists_v1"
        static let favorites = "favorites_v1"
        static let audioSettings = "audio_settings_v1"
        static let trackAudioSettings = "track_audio_settings_v1"
    }

    private let defaults = UserDefaults.standard
    // JSONEncoder/JSONDecoder are not thread-safe for concurrent access, but all callers
    // of PersistenceService.shared invoke it from @MainActor context, so a single shared
    // instance per type is safe here.
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private init() {}

    func savePlaylists(_ playlists: [Playlist]) {
        do {
            defaults.set(try encoder.encode(playlists), forKey: Keys.playlists)
        } catch {
            appError("savePlaylists failed: \(error)", category: "persistence")
        }
    }

    func loadPlaylists() -> [Playlist] {
        guard let data = defaults.data(forKey: Keys.playlists) else { return [] }
        do {
            return try decoder.decode([Playlist].self, from: data)
        } catch {
            appError("loadPlaylists decode failed: \(error)", category: "persistence")
            return []
        }
    }

    func saveFavorites(_ ids: Set<String>) {
        do {
            defaults.set(try encoder.encode(Array(ids)), forKey: Keys.favorites)
        } catch {
            appError("saveFavorites failed: \(error)", category: "persistence")
        }
    }

    func loadFavorites() -> Set<String> {
        guard let data = defaults.data(forKey: Keys.favorites) else { return [] }
        do {
            return Set(try decoder.decode([String].self, from: data))
        } catch {
            appError("loadFavorites decode failed: \(error)", category: "persistence")
            return []
        }
    }

    func saveAudioSettings(_ settings: AudioSettings) {
        do {
            defaults.set(try encoder.encode(settings), forKey: Keys.audioSettings)
        } catch {
            appError("saveAudioSettings failed: \(error)", category: "persistence")
        }
    }

    func loadAudioSettings() -> AudioSettings? {
        guard let data = defaults.data(forKey: Keys.audioSettings) else { return nil }
        do {
            return try decoder.decode(AudioSettings.self, from: data)
        } catch {
            appError("loadAudioSettings decode failed: \(error)", category: "persistence")
            return nil
        }
    }

    /// Per-track audio settings overrides, keyed by `Song.id`. Lets users save
    /// custom EQ/effects for individual tracks that are recalled automatically
    /// whenever that track plays again, separate from the global default settings.
    func saveTrackAudioSettings(_ settings: [String: AudioSettings]) {
        do {
            defaults.set(try encoder.encode(settings), forKey: Keys.trackAudioSettings)
        } catch {
            appError("saveTrackAudioSettings failed: \(error)", category: "persistence")
        }
    }

    func loadTrackAudioSettings() -> [String: AudioSettings] {
        guard let data = defaults.data(forKey: Keys.trackAudioSettings) else { return [:] }
        do {
            return try decoder.decode([String: AudioSettings].self, from: data)
        } catch {
            appError("loadTrackAudioSettings decode failed: \(error)", category: "persistence")
            return [:]
        }
    }
}
