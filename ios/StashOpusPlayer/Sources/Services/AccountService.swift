import Foundation
import UIKit

// MARK: - Models

struct AppUser: Codable, Equatable {
    let id: String
    let username: String
    let displayName: String?
    let email: String?
    let avatarURL: String?

    enum CodingKeys: String, CodingKey {
        case id
        case username
        case displayName = "display_name"
        case email
        case avatarURL   = "avatar_url"
    }
}

struct SyncData: Codable {
    var favorites: [SyncFavorite]
    var playlists: [SyncPlaylist]
    var audioSettingsJSON: String?
    var themeColor: String?

    enum CodingKeys: String, CodingKey {
        case favorites
        case playlists
        case audioSettingsJSON = "audio_settings_json"
        case themeColor        = "theme_color"
    }
}

struct SyncFavorite: Codable {
    let songId: String
    let title: String?
    let artist: String?
    let album: String?

    enum CodingKeys: String, CodingKey {
        case songId = "song_id"
        case title
        case artist
        case album
    }
}

struct SyncPlaylist: Codable {
    let id: String
    let name: String
    let description: String?
    var tracks: [SyncTrack]
}

struct SyncTrack: Codable {
    let localSongId: String?
    let trackUrl: String?
    let title: String
    let artist: String?
    let album: String?
    let durationSeconds: Int?
    let position: Int?

    enum CodingKeys: String, CodingKey {
        case localSongId      = "local_song_id"
        case trackUrl         = "track_url"
        case title
        case artist
        case album
        case durationSeconds  = "duration_seconds"
        case position
    }
}

// MARK: - AccountService

@MainActor
final class AccountService: ObservableObject {

    static let tokenKey = "ios_account_token"
    static let userKey  = "ios_account_user"

    // MARK: Published state

    @Published var isLoggedIn: Bool = false
    @Published var currentUser: AppUser? = nil
    @Published var isSyncing: Bool = false
    @Published var errorMessage: String? = nil
    @Published var lastSyncDate: Date? = nil

    // MARK: Persisted token

    var token: String? {
        get { UserDefaults.standard.string(forKey: Self.tokenKey) }
        set { UserDefaults.standard.set(newValue, forKey: Self.tokenKey) }
    }

    // MARK: Bridge URL (shared with StreamingService)

    var bridgeURL: String {
        UserDefaults.standard.string(forKey: StreamingService.bridgeURLKey) ?? ""
    }

    // MARK: Init — restore session

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.userKey),
           let user = try? JSONDecoder().decode(AppUser.self, from: data) {
            currentUser = user
            isLoggedIn = token != nil
        }
    }

    // MARK: - Public API

    func login(username: String, password: String, deviceName: String = UIDevice.current.name) async {
        errorMessage = nil
        struct Body: Encodable {
            let username: String
            let password: String
            let device_name: String
        }
        do {
            let data = try await makeRequest(
                "/auth/login",
                method: "POST",
                body: Body(username: username, password: password, device_name: deviceName)
            )
            let response = try JSONDecoder().decode(AuthResponse.self, from: data)
            token = response.token
            currentUser = response.user
            isLoggedIn = true
            saveUserLocally(response.user)
        } catch let err as AccountError {
            errorMessage = err.message
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func register(
        username: String,
        password: String,
        email: String?,
        displayName: String?
    ) async {
        errorMessage = nil
        struct Body: Encodable {
            let username: String
            let password: String
            let email: String?
            let display_name: String?
        }
        do {
            let data = try await makeRequest(
                "/auth/register",
                method: "POST",
                body: Body(
                    username: username,
                    password: password,
                    email: email.flatMap { $0.isEmpty ? nil : $0 },
                    display_name: displayName.flatMap { $0.isEmpty ? nil : $0 }
                )
            )
            let response = try JSONDecoder().decode(AuthResponse.self, from: data)
            token = response.token
            currentUser = response.user
            isLoggedIn = true
            saveUserLocally(response.user)
        } catch let err as AccountError {
            errorMessage = err.message
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func logout() async {
        errorMessage = nil
        if token != nil {
            _ = try? await makeRequest("/auth/logout", method: "POST", body: EmptyBody())
        }
        clearSession()
    }

    func refreshMe() async {
        guard isLoggedIn else { return }
        do {
            let data = try await makeRequest("/auth/me")
            let user = try JSONDecoder().decode(AppUser.self, from: data)
            currentUser = user
            saveUserLocally(user)
        } catch let err as AccountError where err.statusCode == 401 {
            clearSession()
        } catch {
            // Non-fatal; keep existing cached user
        }
    }

    // MARK: - Sync

    func pushSync(library: LibraryManager) async {
        guard isLoggedIn else { return }
        isSyncing = true
        errorMessage = nil
        defer { isSyncing = false }

        // Build favorites from library
        let favorites = library.favoriteSongs.map { song in
            SyncFavorite(
                songId: song.id,
                title: song.title,
                artist: song.artistName,
                album: song.albumName
            )
        }

        // Build playlists from library
        let playlists = library.playlists.map { playlist -> SyncPlaylist in
            let songs = playlist.songIDs.compactMap { id in
                library.allSongs.first { $0.id == id }
            }
            let tracks = songs.enumerated().map { idx, song in
                SyncTrack(
                    localSongId: song.id,
                    trackUrl: song.url?.absoluteString,
                    title: song.title,
                    artist: song.artist.isEmpty ? nil : song.artist,
                    album: song.album.isEmpty ? nil : song.album,
                    durationSeconds: Int(song.duration),
                    position: idx
                )
            }
            return SyncPlaylist(
                id: playlist.id.uuidString,
                name: playlist.name,
                description: nil,
                tracks: tracks
            )
        }

        let payload = SyncData(
            favorites: favorites,
            playlists: playlists,
            audioSettingsJSON: nil,
            themeColor: nil
        )

        do {
            _ = try await makeRequest("/user/sync", method: "POST", body: payload)
            lastSyncDate = Date()
        } catch let err as AccountError {
            errorMessage = err.message
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func pullSync(library: LibraryManager) async {
        guard isLoggedIn else { return }
        isSyncing = true
        errorMessage = nil
        defer { isSyncing = false }

        do {
            let data = try await makeRequest("/user/sync")
            let sync = try JSONDecoder().decode(SyncData.self, from: data)

            // Apply favorites: toggle to match remote set
            let remoteIDs = Set(sync.favorites.map { $0.songId })
            let localFavorites = library.favoriteSongIDs
            let toAdd = remoteIDs.subtracting(localFavorites)
            let toRemove = localFavorites.subtracting(remoteIDs)
            for id in toAdd    { library.toggleFavorite(songID: id) }
            for id in toRemove { library.toggleFavorite(songID: id) }

            // Apply playlists: merge server playlists (add missing by name, skip existing)
            let existingNames = Set(library.playlists.map { $0.name })
            for sp in sync.playlists {
                guard !existingNames.contains(sp.name) else { continue }
                library.createPlaylist(name: sp.name)
                // Add any local song IDs that match tracks
                if let newPL = library.playlists.last(where: { $0.name == sp.name }) {
                    for track in sp.tracks {
                        if let sid = track.localSongId {
                            library.addSong(id: sid, toPlaylistID: newPL.id)
                        }
                    }
                }
            }

            lastSyncDate = Date()
        } catch let err as AccountError {
            errorMessage = err.message
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func logPlay(song: Song, listenSeconds: Int) async {
        guard isLoggedIn else { return }
        struct Body: Encodable {
            let title: String
            let artist: String?
            let track_url: String?
            let local_song_id: String?
            let listen_seconds: Int
        }
        _ = try? await makeRequest(
            "/user/history",
            method: "POST",
            body: Body(
                title: song.title,
                artist: song.artist.isEmpty ? nil : song.artist,
                track_url: song.url?.absoluteString,
                local_song_id: song.id,
                listen_seconds: listenSeconds
            )
        )
    }

    // MARK: - Private helpers

    private struct EmptyBody: Encodable {}

    private struct AuthResponse: Decodable {
        let user: AppUser
        let token: String
    }

    private func saveUserLocally(_ user: AppUser) {
        if let data = try? JSONEncoder().encode(user) {
            UserDefaults.standard.set(data, forKey: Self.userKey)
        }
    }

    private func clearSession() {
        token = nil
        currentUser = nil
        isLoggedIn = false
        UserDefaults.standard.removeObject(forKey: Self.userKey)
    }

    func makeRequest<T: Encodable>(_ path: String, method: String = "GET", body: T) async throws -> Data {
        try await _makeRequest(path, method: method, bodyData: try JSONEncoder().encode(body))
    }

    func makeRequest(_ path: String, method: String = "GET") async throws -> Data {
        try await _makeRequest(path, method: method, bodyData: nil)
    }

    private func _makeRequest(_ path: String, method: String, bodyData: Data?) async throws -> Data {
        let base = bridgeURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let normalizedPath = path.hasPrefix("/") ? path : "/\(path)"
        guard let url = URL(string: base + normalizedPath) else {
            throw AccountError(statusCode: 0, message: "Invalid bridge URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 20

        if let tok = token {
            request.setValue("Bearer \(tok)", forHTTPHeaderField: "Authorization")
        }

        if let data = bodyData {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = data
        }

        let (data, response) = try await URLSession.shared.data(for: request)

        if let http = response as? HTTPURLResponse {
            if http.statusCode == 401 {
                clearSession()
                throw AccountError(statusCode: 401, message: "Session expired. Please sign in again.")
            }
            if !(200..<300).contains(http.statusCode) {
                // Try to extract detail from FastAPI error body
                if let detail = try? JSONDecoder().decode(APIErrorBody.self, from: data) {
                    throw AccountError(statusCode: http.statusCode, message: detail.detail)
                }
                throw AccountError(statusCode: http.statusCode, message: "Server error (HTTP \(http.statusCode))")
            }
        }

        return data
    }
}

// MARK: - Error types

struct AccountError: LocalizedError {
    let statusCode: Int
    let message: String

    var errorDescription: String? { message }
}

private struct APIErrorBody: Decodable {
    let detail: String
}
