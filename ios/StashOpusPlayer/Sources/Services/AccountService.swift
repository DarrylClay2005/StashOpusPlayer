import Foundation
import SwiftUI
import UIKit

// MARK: - Models

struct AppUser: Codable, Equatable {
    let id: String
    let username: String
    let displayName: String?
    let email: String?
    let avatarURL: String?
    let dateOfBirth: String?   // ISO YYYY-MM-DD, nil if not set

    enum CodingKeys: String, CodingKey {
        case id
        case username
        case displayName  = "display_name"
        case email
        case avatarURL    = "avatar_url"
        case dateOfBirth  = "date_of_birth"
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

    static let tokenKey       = "ios_account_token"
    static let userKey        = "ios_account_user"
    static let lastSyncKey    = "ios_account_last_sync"

    // MARK: Published state

    @Published var isLoggedIn: Bool = false
    @Published var currentUser: AppUser? = nil
    @Published var isSyncing: Bool = false
    @Published var errorMessage: String? = nil
    @Published var lastSyncDate: Date? = nil {
        didSet {
            if let d = lastSyncDate {
                UserDefaults.standard.set(d.timeIntervalSince1970, forKey: Self.lastSyncKey)
            }
        }
    }
    @Published var avatarImage: UIImage? = nil
    @Published private(set) var hasDateOfBirth: Bool = false

    // MARK: Persisted token

    var token: String? {
        get { UserDefaults.standard.string(forKey: Self.tokenKey) }
        set { UserDefaults.standard.set(newValue, forKey: Self.tokenKey) }
    }

    // MARK: Debounce state

    private var syncDebounceTask: Task<Void, Never>?

    // MARK: Auto-push timer

    private var autoPushTimer: Timer?

    func startAutoPushTimer(library: LibraryManager) {
        stopAutoPushTimer()
        autoPushTimer = Timer.scheduledTimer(withTimeInterval: 8 * 60, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.isLoggedIn else { return }
                await self.pushSync(library: library)
            }
        }
    }

    func stopAutoPushTimer() {
        autoPushTimer?.invalidate()
        autoPushTimer = nil
    }

    /// Schedules a push sync that fires 2 seconds after the last call.
    /// Rapid successive mutations only trigger one server write.
    func schedulePush(library: LibraryManager, audioSettings: AudioSettings? = nil) {
        guard isLoggedIn else { return }
        syncDebounceTask?.cancel()
        syncDebounceTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
            guard let self, !Task.isCancelled, self.isLoggedIn else { return }
            await self.pushSync(library: library, audioSettings: audioSettings)
        }
    }

    // MARK: Bridge URL — defaults to public baked-in URL, overridable in Settings

    var bridgeURL: String {
        UserDefaults.standard.string(forKey: StreamingService.bridgeURLKey)
            ?? StreamingService.defaultBridgeURL
    }

    // MARK: Init / Deinit

    deinit {
        syncDebounceTask?.cancel()
        autoPushTimer?.invalidate()
    }

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.userKey),
           let user = try? JSONDecoder().decode(AppUser.self, from: data) {
            currentUser = user
            isLoggedIn = token != nil
        }
        let ts = UserDefaults.standard.double(forKey: Self.lastSyncKey)
        if ts > 0 {
            // Bypass didSet to avoid re-writing the same value on init
            _lastSyncDate = Published(initialValue: Date(timeIntervalSince1970: ts))
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
            hasDateOfBirth = response.user.dateOfBirth != nil
            saveUserLocally(response.user)
            await loadAvatar(forceRefresh: true)
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
            hasDateOfBirth = response.user.dateOfBirth != nil
            saveUserLocally(response.user)
            await loadAvatar(forceRefresh: true)
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
            hasDateOfBirth = user.dateOfBirth != nil
            saveUserLocally(user)
        } catch let err as AccountError where err.statusCode == 401 {
            clearSession()
        } catch {
            // Non-fatal; keep existing cached user
        }
    }

    /// Update the display name on the server and locally.
    func updateDisplayName(_ newName: String) async {
        guard isLoggedIn else { return }
        errorMessage = nil
        struct Body: Encodable { let display_name: String }
        do {
            let data = try await makeRequest("/auth/me", method: "PUT", body: Body(display_name: newName))
            let user = try JSONDecoder().decode(AppUser.self, from: data)
            currentUser = user
            hasDateOfBirth = user.dateOfBirth != nil
            saveUserLocally(user)
        } catch let err as AccountError {
            errorMessage = err.message
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Sync

    /// Call schedulePush instead of this directly — it debounces rapid mutations.
    func pushSync(library: LibraryManager, audioSettings: AudioSettings? = nil) async {
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

        // Serialize audio settings to JSON if provided
        let audioJSON: String? = audioSettings.flatMap { settings in
            (try? JSONEncoder().encode(settings)).flatMap { String(data: $0, encoding: .utf8) }
        }
        // Read current accent colour from UserDefaults (saved by AppTheme.saveAccentColor)
        let themeHex: String? = {
            guard let data = UserDefaults.standard.data(forKey: "accent_color_data"),
                  let uiColor = try? NSKeyedUnarchiver.unarchivedObject(ofClass: UIColor.self, from: data)
            else { return nil }
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            uiColor.getRed(&r, green: &g, blue: &b, alpha: &a)
            return String(format: "#%02X%02X%02X", Int(r*255), Int(g*255), Int(b*255))
        }()

        let payload = SyncData(
            favorites: favorites,
            playlists: playlists,
            audioSettingsJSON: audioJSON,
            themeColor: themeHex ?? "#EC4079"
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

            // Restore audio settings from DB and save locally so player can pick them up
            if let json = sync.audioSettingsJSON,
               let jsonData = json.data(using: .utf8),
               let restoredSettings = try? JSONDecoder().decode(AudioSettings.self, from: jsonData) {
                PersistenceService.shared.saveAudioSettings(restoredSettings)
                // Signal the player to apply them (observers in StashOpusPlayerApp reload on launch)
            }

            // Restore theme colour
            if let hex = sync.themeColor, hex.hasPrefix("#"), hex.count == 7 {
                let scanner = Scanner(string: String(hex.dropFirst()))
                var rgb: UInt64 = 0
                if scanner.scanHexInt64(&rgb) {
                    let r = CGFloat((rgb >> 16) & 0xFF) / 255
                    let g = CGFloat((rgb >> 8)  & 0xFF) / 255
                    let b = CGFloat( rgb        & 0xFF) / 255
                    AppTheme.saveAccentColor(Color(red: r, green: g, blue: b))
                }
            }

            lastSyncDate = Date()
        } catch let err as AccountError {
            errorMessage = err.message
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - DOB

    /// Set date of birth (ISO YYYY-MM-DD). Server enforces immutability once set.
    func setDateOfBirth(_ dob: String) async {
        guard isLoggedIn else { return }
        errorMessage = nil
        struct Body: Encodable { let date_of_birth: String }
        do {
            _ = try await makeRequest("/auth/me", method: "PUT", body: Body(date_of_birth: dob))
            hasDateOfBirth = true
        } catch let err as AccountError {
            errorMessage = err.message
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Avatar

    /// Upload a profile picture as JPEG (max 1 MB enforced server-side).
    func uploadAvatar(image: UIImage) async {
        guard isLoggedIn else { return }
        guard let jpeg = image.jpegData(compressionQuality: 0.8) else { return }
        guard var req = makeBaseRequest("/user/avatar", method: "POST") else { return }
        req.setValue("image/jpeg", forHTTPHeaderField: "Content-Type")
        req.httpBody = jpeg
        _ = try? await URLSession.shared.data(for: req)
        avatarImage = image
        saveAvatarLocally(image)
    }

    /// Load avatar from local cache first, then from server. Updates `avatarImage`.
    func loadAvatar(forceRefresh: Bool = false) async {
        if !forceRefresh, let cached = loadAvatarLocally() {
            avatarImage = cached
            return
        }
        guard isLoggedIn, let userId = currentUser?.id else { return }
        guard let req = makeBaseRequest("/user/avatar/\(userId)", method: "GET") else { return }
        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              (resp as? HTTPURLResponse)?.statusCode == 200,
              let img = UIImage(data: data) else { return }
        avatarImage = img
        saveAvatarLocally(img)
    }

    private func makeBaseRequest(_ path: String, method: String) -> URLRequest? {
        let base = bridgeURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: base + path) else { return nil }
        var req = URLRequest(url: url)
        req.httpMethod = method
        if let t = token, !t.isEmpty {
            req.setValue("Bearer \(t)", forHTTPHeaderField: "Authorization")
        }
        return req
    }

    private func saveAvatarLocally(_ image: UIImage) {
        let url = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("user_avatar.jpg")
        image.jpegData(compressionQuality: 0.8).flatMap { try? $0.write(to: url) }
    }

    private func loadAvatarLocally() -> UIImage? {
        let url = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("user_avatar.jpg")
        return (try? Data(contentsOf: url)).flatMap { UIImage(data: $0) }
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
        hasDateOfBirth = false
        avatarImage = nil
        stopAutoPushTimer()
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
