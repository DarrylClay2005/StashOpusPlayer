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
    var shareListeningActivity: Bool = false

    enum CodingKeys: String, CodingKey {
        case id
        case username
        case displayName  = "display_name"
        case email
        case avatarURL    = "avatar_url"
        case dateOfBirth  = "date_of_birth"
        case shareListeningActivity = "share_listening_activity"
    }
}

struct SyncData: Codable {
    var favorites: [SyncFavorite]
    var playlists: [SyncPlaylist]
    var audioSettingsJSON: String?
    var trackAudioSettingsJSON: String?
    var themeColor: String?

    enum CodingKeys: String, CodingKey {
        case favorites
        case playlists
        case audioSettingsJSON      = "audio_settings_json"
        case trackAudioSettingsJSON = "track_audio_settings_json"
        case themeColor             = "theme_color"
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
    var folder: String?
    var tags: [String]
    var tracks: [SyncTrack]

    enum CodingKeys: String, CodingKey {
        case id, name, description, folder, tags, tracks
    }

    init(id: String, name: String, description: String?, folder: String? = nil, tags: [String] = [], tracks: [SyncTrack]) {
        self.id = id
        self.name = name
        self.description = description
        self.folder = folder
        self.tags = tags
        self.tracks = tracks
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        folder = try container.decodeIfPresent(String.self, forKey: .folder)
        tags = try container.decodeIfPresent([String].self, forKey: .tags) ?? []
        tracks = try container.decodeIfPresent([SyncTrack].self, forKey: .tracks) ?? []
    }
}

/// Metadata for an automatic server-side backup of this user's sync data
/// (favorites/playlists/settings), taken before every push (and before every
/// restore). See `ios_user_backups` / GET+POST `/user/backups...` on the bridge.
struct SyncBackup: Codable, Identifiable {
    let id: String
    let reason: String
    let createdAt: String
    let favoriteCount: Int
    let playlistCount: Int

    enum CodingKeys: String, CodingKey {
        case id
        case reason
        case createdAt     = "created_at"
        case favoriteCount = "favorite_count"
        case playlistCount = "playlist_count"
    }

    /// `created_at` parsed as a `Date`, for display with relative formatting.
    var date: Date? {
        ISO8601DateFormatter().date(from: createdAt)
    }

    var reasonDisplayName: String {
        switch reason {
        case "pre_push":    return "Before sync"
        case "pre_restore": return "Before restore"
        default:            return reason
        }
    }
}

/// A single entry in the "what others are listening to" feed (GET /social/activity).
/// Only ever contains title/artist/played_at plus public profile info — never
/// file contents or URLs.
struct ActivityEntry: Codable, Identifiable {
    let username: String
    let displayName: String?
    let avatarURL: String?
    let title: String?
    let artist: String?
    let playedAt: String?

    var id: String { "\(username)-\(playedAt ?? "")-\(title ?? "")" }

    enum CodingKeys: String, CodingKey {
        case username
        case displayName = "display_name"
        case avatarURL   = "avatar_url"
        case title
        case artist
        case playedAt    = "played_at"
    }

    var date: Date? {
        guard let playedAt else { return nil }
        return ISO8601DateFormatter().date(from: playedAt)
    }
}

/// A trending track from GET /social/discover — aggregated across users who've
/// opted in to sharing listening activity.
struct TrendingTrack: Codable, Identifiable {
    let title: String
    let artist: String?
    let playCount: Int
    let listenerCount: Int

    var id: String { "\(title)-\(artist ?? "")" }

    enum CodingKeys: String, CodingKey {
        case title
        case artist
        case playCount     = "play_count"
        case listenerCount = "listener_count"
    }
}

/// One active login (device/session) for this account — GET /auth/sessions.
struct AccountSession: Codable, Identifiable {
    let tokenId: String
    let deviceName: String?
    let createdAt: String
    let expiresAt: String?
    let isCurrent: Bool

    var id: String { tokenId }

    enum CodingKeys: String, CodingKey {
        case tokenId    = "token_id"
        case deviceName = "device_name"
        case createdAt  = "created_at"
        case expiresAt  = "expires_at"
        case isCurrent  = "is_current"
    }

    var createdDate: Date? {
        ISO8601DateFormatter().date(from: createdAt)
    }
}

/// Lifetime listening stats from GET /user/stats.
struct AccountStats: Codable {
    let totalPlays: Int
    let totalListenSeconds: Int
    let topArtists: [TopArtist]
    let topTracks: [TopTrack]

    enum CodingKeys: String, CodingKey {
        case totalPlays         = "total_plays"
        case totalListenSeconds = "total_listen_seconds"
        case topArtists         = "top_artists"
        case topTracks          = "top_tracks"
    }

    struct TopArtist: Codable, Identifiable {
        let artist: String
        let playCount: Int
        var id: String { artist }
        enum CodingKeys: String, CodingKey { case artist, playCount = "play_count" }
    }

    struct TopTrack: Codable, Identifiable {
        let title: String
        let artist: String?
        let playCount: Int
        var id: String { "\(title)-\(artist ?? "")" }
        enum CodingKeys: String, CodingKey { case title, artist, playCount = "play_count" }
    }
}

/// One collaborator entry from GET /user/playlists/{id}/collaborators.
struct PlaylistCollaborator: Decodable, Identifiable {
    let userId: String
    let username: String
    let role: String
    let addedAt: String?

    var id: String { userId }

    enum CodingKeys: String, CodingKey {
        case userId   = "user_id"
        case username
        case role
        case addedAt  = "added_at"
    }
}

/// One entry from GET /user/playlists/shared-with-me.
struct SharedPlaylist: Decodable, Identifiable {
    let id: String
    let name: String
    let description: String?
    let role: String
    let ownerUsername: String
    let updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case id, name, description, role
        case ownerUsername = "owner_username"
        case updatedAt     = "updated_at"
    }
}

/// One track within GET /user/playlists/{id}.
struct SharedPlaylistTrack: Decodable {
    let trackUrl: String?
    let localSongId: String?
    let title: String
    let artist: String?
    let album: String?
    let durationSeconds: Int?

    enum CodingKeys: String, CodingKey {
        case trackUrl        = "track_url"
        case localSongId     = "local_song_id"
        case title, artist, album
        case durationSeconds = "duration_seconds"
    }
}

/// Full playlist (with tracks) from GET /user/playlists/{id}.
struct SharedPlaylistDetail: Decodable {
    let id: String
    let name: String
    let description: String?
    let role: String
    let tracks: [SharedPlaylistTrack]
}

/// One track from GET /user/queue.
struct QueueItem: Decodable {
    let localSongId: String?
    let trackUrl: String?
    let title: String
    let artist: String?
    let album: String?
    let durationSeconds: Int?

    enum CodingKeys: String, CodingKey {
        case localSongId      = "local_song_id"
        case trackUrl         = "track_url"
        case title, artist, album
        case durationSeconds  = "duration_seconds"
    }
}

/// Listening streaks and badge unlocks from GET /user/achievements.
struct AchievementsData: Codable {
    let totalPlays: Int
    let totalListenSeconds: Int
    let currentStreakDays: Int
    let longestStreakDays: Int
    let badges: [String]

    enum CodingKeys: String, CodingKey {
        case totalPlays         = "total_plays"
        case totalListenSeconds = "total_listen_seconds"
        case currentStreakDays  = "current_streak_days"
        case longestStreakDays  = "longest_streak_days"
        case badges
    }
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
    @Published var backups: [SyncBackup] = []
    @Published var socialActivity: [ActivityEntry] = []
    @Published var trendingTracks: [TrendingTrack] = []
    @Published var sessions: [AccountSession] = []
    @Published var stats: AccountStats? = nil
    @Published var achievements: AchievementsData? = nil
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
    func schedulePush(
        library: LibraryManager,
        audioSettings: AudioSettings? = nil,
        trackAudioSettings: [String: AudioSettings]? = nil
    ) {
        guard isLoggedIn else { return }
        syncDebounceTask?.cancel()
        syncDebounceTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
            guard let self, !Task.isCancelled, self.isLoggedIn else { return }
            await self.pushSync(library: library, audioSettings: audioSettings, trackAudioSettings: trackAudioSettings)
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

    /// Ambient reference to the app's single AccountService instance, so
    /// services without direct access to the SwiftUI environment (e.g.
    /// AudioPlayerManager) can push playback state. Set once at init.
    static weak var shared: AccountService?

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.userKey),
           let user = try? JSONDecoder().decode(AppUser.self, from: data) {
            currentUser = user
            isLoggedIn = token != nil
            hasDateOfBirth = user.dateOfBirth != nil
        }
        let ts = UserDefaults.standard.double(forKey: Self.lastSyncKey)
        if ts > 0 {
            // Bypass didSet to avoid re-writing the same value on init
            _lastSyncDate = Published(initialValue: Date(timeIntervalSince1970: ts))
        }
        Self.shared = self
    }

    // MARK: - Public API

    func login(username: String, password: String, deviceName: String = UIDevice.current.name) async {
        appLog("Login attempt: \(username)", category: "account")
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
            appLog("Login success: \(username) (id: \(response.user.id))", category: "account")
            await loadAvatar(forceRefresh: true)
        } catch let err as AccountError {
            appError("Login failed [\(err.statusCode)]: \(err.message)", category: "account")
            errorMessage = err.message
        } catch {
            appError("Login error: \(error.localizedDescription)", category: "account")
            errorMessage = error.localizedDescription
        }
    }

    func register(
        username: String,
        password: String,
        email: String?,
        displayName: String?
    ) async {
        appLog("Register attempt: \(username)", category: "account")
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
            appLog("Register success: \(username) (id: \(response.user.id))", category: "account")
            await loadAvatar(forceRefresh: true)
        } catch let err as AccountError {
            appError("Register failed [\(err.statusCode)]: \(err.message)", category: "account")
            errorMessage = err.message
        } catch {
            appError("Register error: \(error.localizedDescription)", category: "account")
            errorMessage = error.localizedDescription
        }
    }

    func logout() async {
        appLog("Logout: \(currentUser?.username ?? "?")", category: "account")
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
            appLog("refreshMe: updated profile for \(user.username)", category: "account")
        } catch let err as AccountError where err.statusCode == 401 {
            appWarn("refreshMe: session expired, clearing", category: "account")
            clearSession()
        } catch {
            appWarn("refreshMe: \(error.localizedDescription) — using cached user", category: "account")
        }
    }

    /// Update the display name on the server and locally.
    func updateDisplayName(_ newName: String) async {
        guard isLoggedIn else { return }
        appLog("updateDisplayName: \"\(newName)\"", category: "account")
        errorMessage = nil
        struct Body: Encodable { let display_name: String }
        do {
            let data = try await makeRequest("/auth/me", method: "PUT", body: Body(display_name: newName))
            let user = try JSONDecoder().decode(AppUser.self, from: data)
            currentUser = user
            hasDateOfBirth = user.dateOfBirth != nil
            saveUserLocally(user)
            appLog("updateDisplayName: success", category: "account")
        } catch let err as AccountError {
            appError("updateDisplayName failed [\(err.statusCode)]: \(err.message)", category: "account")
            errorMessage = err.message
        } catch {
            appError("updateDisplayName error: \(error.localizedDescription)", category: "account")
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Sync

    /// Call schedulePush instead of this directly — it debounces rapid mutations.
    func pushSync(
        library: LibraryManager,
        audioSettings: AudioSettings? = nil,
        trackAudioSettings: [String: AudioSettings]? = nil
    ) async {
        guard isLoggedIn else { return }
        appLog("Push sync started (favorites: \(library.favoriteSongIDs.count), playlists: \(library.playlists.count))", category: "account")
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
                folder: playlist.folder,
                tags: playlist.tags,
                tracks: tracks
            )
        }

        // Serialize audio settings to JSON if provided
        let audioJSON: String? = audioSettings.flatMap { settings in
            (try? JSONEncoder().encode(settings)).flatMap { String(data: $0, encoding: .utf8) }
        }
        // Serialize per-track audio settings overrides to JSON if provided
        let trackAudioJSON: String? = trackAudioSettings.flatMap { map in
            (try? JSONEncoder().encode(map)).flatMap { String(data: $0, encoding: .utf8) }
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
            trackAudioSettingsJSON: trackAudioJSON,
            themeColor: themeHex ?? "#EC4079"
        )

        do {
            _ = try await makeRequest("/user/sync", method: "POST", body: payload)
            lastSyncDate = Date()
            appLog("Push sync complete", category: "account")
        } catch let err as AccountError {
            appError("Push sync failed [\(err.statusCode)]: \(err.message)", category: "account")
            errorMessage = err.message
        } catch {
            appError("Push sync error: \(error.localizedDescription)", category: "account")
            errorMessage = error.localizedDescription
        }
    }

    func pullSync(library: LibraryManager, player: AudioPlayerManager? = nil) async {
        guard isLoggedIn else { return }
        appLog("Pull sync started", category: "account")
        isSyncing = true
        errorMessage = nil
        defer { isSyncing = false }

        do {
            let data = try await makeRequest("/user/sync")
            let sync = try JSONDecoder().decode(SyncData.self, from: data)

            // Apply favorites: merge remote into local — add anything missing locally.
            //
            // This used to be a destructive "toggle to match remote exactly", which
            // also *removed* any local favorite absent from the server payload. That
            // silently wiped out the user's likes whenever the remote was behind the
            // device (e.g. the previous session's pushSync hadn't completed before
            // the app was terminated, or ran against a flaky connection) — which is
            // exactly what showed up as "app data doesn't seem to hold anything
            // locally". Only ever add; the merged superset gets pushed back up by
            // the `.onChange(of: favoriteSongIDs)` → schedulePush handler, so both
            // sides converge without data loss.
            let remoteIDs = Set(sync.favorites.map { $0.songId })
            let localFavorites = library.favoriteSongIDs
            let toAdd = remoteIDs.subtracting(localFavorites)
            for id in toAdd { library.toggleFavorite(songID: id) }

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
                    if sp.folder != nil { library.setFolder(sp.folder, forPlaylistID: newPL.id) }
                    if !sp.tags.isEmpty { library.setTags(sp.tags, forPlaylistID: newPL.id) }
                }
            }

            // Restore audio settings from DB — but only as a first-run/new-device
            // bootstrap (no local settings yet). Unconditionally overwriting local
            // settings with whatever the server last received clobbers more recent
            // local changes whenever a previous pushSync didn't finish before the
            // app was terminated (the debounced 2s push is easy to race on app
            // close), which presents to the user as "my settings keep resetting /
            // don't actually save". The local copy — which `onChange` keeps pushed
            // up via schedulePush — is always at least as fresh as the server's.
            if PersistenceService.shared.loadAudioSettings() == nil,
               let json = sync.audioSettingsJSON,
               let jsonData = json.data(using: .utf8),
               let restoredSettings = try? JSONDecoder().decode(AudioSettings.self, from: jsonData) {
                PersistenceService.shared.saveAudioSettings(restoredSettings)
                // Signal the player to apply them (observers in LumisoundApp reload on launch)
            }

            // Restore per-track audio settings overrides — same first-run-only
            // guard as the global audio settings above, to avoid clobbering
            // settings saved locally since the last successful push.
            if PersistenceService.shared.loadTrackAudioSettings().isEmpty,
               let json = sync.trackAudioSettingsJSON,
               let jsonData = json.data(using: .utf8),
               let restoredMap = try? JSONDecoder().decode([String: AudioSettings].self, from: jsonData),
               !restoredMap.isEmpty {
                if let player {
                    player.restorePerTrackAudioSettings(restoredMap)
                } else {
                    PersistenceService.shared.saveTrackAudioSettings(restoredMap)
                }
            }

            // Restore theme colour — same first-run-only guard as audio settings above:
            // there's no `.onChange` hook pushing accent-colour changes immediately
            // (it only rides along on the next favorites/playlist/settings push), so
            // an unconditional overwrite here would routinely revert a just-picked
            // colour back to whatever stale value the server last happened to receive.
            if UserDefaults.standard.data(forKey: "accent_color_data") == nil,
               let hex = sync.themeColor, hex.hasPrefix("#"), hex.count == 7 {
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
            appLog("Pull sync complete (favorites: \(remoteIDs.count), playlists: \(sync.playlists.count))", category: "account")
        } catch let err as AccountError {
            appError("Pull sync failed [\(err.statusCode)]: \(err.message)", category: "account")
            errorMessage = err.message
        } catch {
            appError("Pull sync error: \(error.localizedDescription)", category: "account")
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Queue sync

    /// Replaces the server's "up next" queue with `songs`, in order, so it
    /// survives app restarts and syncs across devices (PUT /user/queue).
    /// Fire-and-forget — failures are logged but not surfaced as errors,
    /// since this runs automatically in the background whenever the queue changes.
    func pushQueue(_ songs: [Song]) async {
        guard isLoggedIn else { return }
        struct TrackBody: Encodable {
            let local_song_id: String?
            let track_url: String?
            let title: String
            let artist: String?
            let album: String?
            let duration_seconds: Int
        }
        struct Body: Encodable { let tracks: [TrackBody] }
        let tracks = songs.map { song in
            TrackBody(
                local_song_id: song.persistentID == nil ? song.id : nil,
                track_url: song.url?.absoluteString,
                title: song.title,
                artist: song.artist.isEmpty ? nil : song.artist,
                album: song.album.isEmpty ? nil : song.album,
                duration_seconds: Int(song.duration)
            )
        }
        do {
            _ = try await makeRequest("/user/queue", method: "PUT", body: Body(tracks: tracks))
        } catch {
            appLog("Queue sync push failed: \(error.localizedDescription)", category: "account")
        }
    }

    /// Fetches the server's "up next" queue (GET /user/queue), resolving each
    /// entry against the local library (by ID) or as a streaming track (by URL).
    /// Entries that can't be resolved either way are skipped.
    func fetchQueue(library: LibraryManager) async -> [Song] {
        guard isLoggedIn else { return [] }
        do {
            let data = try await makeRequest("/user/queue")
            let items = try JSONDecoder().decode([QueueItem].self, from: data)
            let songsByID = Dictionary(uniqueKeysWithValues: library.allSongs.map { ($0.id, $0) })
            return items.compactMap { item -> Song? in
                if let localID = item.localSongId, let song = songsByID[localID] {
                    return song
                }
                if let urlString = item.trackUrl, let url = URL(string: urlString) {
                    return Song(
                        title: item.title,
                        artist: item.artist ?? "",
                        album: item.album ?? "",
                        duration: TimeInterval(item.durationSeconds ?? 0),
                        url: url
                    )
                }
                return nil
            }
        } catch let err as AccountError {
            errorMessage = err.message
            return []
        } catch {
            errorMessage = error.localizedDescription
            return []
        }
    }

    // MARK: - Collaborative playlists

    /// Adds (or updates) a collaborator on a playlist this user owns.
    /// `role` must be "editor" or "viewer". Returns true on success.
    func addCollaborator(playlistId: String, username: String, role: String) async -> Bool {
        guard isLoggedIn else { return false }
        struct Body: Encodable { let username: String; let role: String }
        do {
            _ = try await makeRequest("/user/playlists/\(playlistId)/collaborators", method: "POST", body: Body(username: username, role: role))
            return true
        } catch let err as AccountError {
            errorMessage = err.message
            return false
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    /// Lists collaborators on a playlist (owner or collaborator can view).
    func fetchCollaborators(playlistId: String) async -> [PlaylistCollaborator] {
        guard isLoggedIn else { return [] }
        do {
            let data = try await makeRequest("/user/playlists/\(playlistId)/collaborators")
            return try JSONDecoder().decode([PlaylistCollaborator].self, from: data)
        } catch let err as AccountError {
            errorMessage = err.message
            return []
        } catch {
            errorMessage = error.localizedDescription
            return []
        }
    }

    /// Removes a collaborator. The owner can remove anyone; a collaborator can remove themselves.
    func removeCollaborator(playlistId: String, userId: String) async -> Bool {
        guard isLoggedIn else { return false }
        do {
            _ = try await makeRequest("/user/playlists/\(playlistId)/collaborators/\(userId)", method: "DELETE")
            return true
        } catch let err as AccountError {
            errorMessage = err.message
            return false
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    /// Playlists owned by other users that this user can view/edit (GET /user/playlists/shared-with-me).
    func fetchSharedPlaylists() async -> [SharedPlaylist] {
        guard isLoggedIn else { return [] }
        do {
            let data = try await makeRequest("/user/playlists/shared-with-me")
            return try JSONDecoder().decode([SharedPlaylist].self, from: data)
        } catch let err as AccountError {
            errorMessage = err.message
            return []
        } catch {
            errorMessage = error.localizedDescription
            return []
        }
    }

    /// Fetches a single playlist (with tracks) — used to open a shared playlist.
    func fetchPlaylistDetail(playlistId: String) async -> SharedPlaylistDetail? {
        guard isLoggedIn else { return nil }
        do {
            let data = try await makeRequest("/user/playlists/\(playlistId)")
            return try JSONDecoder().decode(SharedPlaylistDetail.self, from: data)
        } catch let err as AccountError {
            errorMessage = err.message
            return nil
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    // MARK: - Backups

    /// Fetches the list of automatic server-side sync backups for this user
    /// (taken before every push and every restore — see `ios_user_backups`).
    func fetchBackups() async {
        guard isLoggedIn else { return }
        do {
            let data = try await makeRequest("/user/backups")
            struct Response: Decodable { let backups: [SyncBackup] }
            let decoded = try JSONDecoder().decode(Response.self, from: data)
            backups = decoded.backups
        } catch let err as AccountError {
            errorMessage = err.message
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Restores a server-side backup, replacing this account's favorites/
    /// playlists/settings with the snapshot, then merges the restored data
    /// down to this device via the normal `pullSync` path.
    func restoreBackup(id: String, library: LibraryManager, player: AudioPlayerManager? = nil) async {
        guard isLoggedIn else { return }
        appLog("Restoring backup \(id)", category: "account")
        isSyncing = true
        errorMessage = nil
        defer { isSyncing = false }

        do {
            _ = try await makeRequest("/user/backups/\(id)/restore", method: "POST")
            await pullSync(library: library, player: player)
            await fetchBackups()
            appLog("Backup restore complete", category: "account")
        } catch let err as AccountError {
            appError("Backup restore failed [\(err.statusCode)]: \(err.message)", category: "account")
            errorMessage = err.message
        } catch {
            appError("Backup restore error: \(error.localizedDescription)", category: "account")
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Social: listening activity & discovery

    /// Toggles whether this account's recent plays are visible to other
    /// signed-in users (title/artist only — see GET /social/activity).
    func setShareListeningActivity(_ enabled: Bool) async {
        guard isLoggedIn else { return }
        struct Body: Encodable { let share_listening_activity: Bool }
        do {
            _ = try await makeRequest("/user/privacy", method: "PUT", body: Body(share_listening_activity: enabled))
            if var user = currentUser {
                user.shareListeningActivity = enabled
                currentUser = user
                if let data = try? JSONEncoder().encode(user) {
                    UserDefaults.standard.set(data, forKey: Self.userKey)
                }
            }
        } catch let err as AccountError {
            errorMessage = err.message
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Fetches the recent "what others are listening to" feed.
    func fetchSocialActivity() async {
        guard isLoggedIn else { return }
        do {
            let data = try await makeRequest("/social/activity")
            struct Response: Decodable { let activity: [ActivityEntry] }
            socialActivity = try JSONDecoder().decode(Response.self, from: data).activity
        } catch let err as AccountError {
            errorMessage = err.message
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Fetches trending tracks aggregated across users sharing activity.
    func fetchTrendingTracks() async {
        guard isLoggedIn else { return }
        do {
            let data = try await makeRequest("/social/discover")
            struct Response: Decodable { let tracks: [TrendingTrack] }
            trendingTracks = try JSONDecoder().decode(Response.self, from: data).tracks
        } catch let err as AccountError {
            errorMessage = err.message
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Stats

    /// Fetches lifetime listening stats (total plays/time, top artists/tracks).
    func fetchStats() async {
        guard isLoggedIn else { return }
        do {
            let data = try await makeRequest("/user/stats")
            stats = try JSONDecoder().decode(AccountStats.self, from: data)
        } catch let err as AccountError {
            errorMessage = err.message
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Fetches listening streaks and badge unlocks (derived server-side from play history).
    func fetchAchievements() async {
        guard isLoggedIn else { return }
        do {
            let data = try await makeRequest("/user/achievements")
            achievements = try JSONDecoder().decode(AchievementsData.self, from: data)
        } catch let err as AccountError {
            errorMessage = err.message
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Sessions (active logins)

    /// Fetches this account's active sessions (one per signed-in device).
    func fetchSessions() async {
        guard isLoggedIn else { return }
        do {
            let data = try await makeRequest("/auth/sessions")
            struct Response: Decodable { let sessions: [AccountSession] }
            sessions = try JSONDecoder().decode(Response.self, from: data).sessions
        } catch let err as AccountError {
            errorMessage = err.message
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Revokes a session by token ID. If it's the current device's session,
    /// also clears the local session (the user is effectively signed out).
    func revokeSession(tokenId: String) async {
        guard isLoggedIn else { return }
        do {
            _ = try await makeRequest("/auth/sessions/\(tokenId)", method: "DELETE")
            if sessions.first(where: { $0.tokenId == tokenId })?.isCurrent == true {
                clearSession()
                return
            }
            await fetchSessions()
        } catch let err as AccountError {
            errorMessage = err.message
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Generates a long-lived (365-day) "RPC setup" token for local tools
    /// like the Discord Rich Presence bridge, so the user never has to put
    /// their account password in a desktop config file. The token shows up
    /// as a regular session ("Discord RPC Bridge") and can be revoked from
    /// Active Sessions.
    func generateRpcToken() async -> String? {
        guard isLoggedIn else { return nil }
        do {
            let data = try await makeRequest("/user/rpc-token", method: "POST")
            struct Response: Decodable { let token: String; let expires_at: String }
            return try JSONDecoder().decode(Response.self, from: data).token
        } catch let err as AccountError {
            errorMessage = err.message
            return nil
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    // MARK: - Password / Account deletion

    /// Changes the account password. On success, every other device is
    /// signed out by the server (see POST /auth/change-password).
    func changePassword(currentPassword: String, newPassword: String) async -> Bool {
        guard isLoggedIn else { return false }
        struct Body: Encodable { let current_password: String; let new_password: String }
        do {
            _ = try await makeRequest(
                "/auth/change-password", method: "POST",
                body: Body(current_password: currentPassword, new_password: newPassword)
            )
            errorMessage = nil
            return true
        } catch let err as AccountError {
            errorMessage = err.message
            return false
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    /// Permanently deletes the account and all server-side data. Requires
    /// the current password. Clears the local session on success.
    func deleteAccount(password: String) async -> Bool {
        guard isLoggedIn else { return false }
        struct Body: Encodable { let password: String }
        do {
            _ = try await makeRequest("/auth/delete-account", method: "POST", body: Body(password: password))
            appLog("Account deleted", category: "account")
            clearSession()
            return true
        } catch let err as AccountError {
            errorMessage = err.message
            return false
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    // MARK: - DOB

    /// Set date of birth (ISO YYYY-MM-DD). Server enforces immutability once set.
    func setDateOfBirth(_ dob: String) async {
        guard isLoggedIn else { return }
        appLog("setDateOfBirth: setting DOB", category: "account")
        errorMessage = nil
        struct Body: Encodable { let date_of_birth: String }
        do {
            _ = try await makeRequest("/auth/me", method: "PUT", body: Body(date_of_birth: dob))
            hasDateOfBirth = true
            appLog("setDateOfBirth: success", category: "account")
        } catch let err as AccountError {
            appError("setDateOfBirth failed [\(err.statusCode)]: \(err.message)", category: "account")
            errorMessage = err.message
        } catch {
            appError("setDateOfBirth error: \(error.localizedDescription)", category: "account")
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Avatar

    /// Upload a profile picture as JPEG (max 1 MB enforced server-side).
    func uploadAvatar(image: UIImage) async {
        guard isLoggedIn else { return }
        guard let jpeg = image.jpegData(compressionQuality: 0.8) else {
            appWarn("uploadAvatar: could not encode image as JPEG", category: "account")
            return
        }
        guard var req = makeBaseRequest("/user/avatar", method: "POST") else {
            appWarn("uploadAvatar: could not build request", category: "account")
            return
        }
        req.setValue("image/jpeg", forHTTPHeaderField: "Content-Type")
        req.httpBody = jpeg
        appLog("uploadAvatar: uploading \(jpeg.count / 1024)KB", category: "account")
        do {
            let (_, resp) = try await URLSession.shared.data(for: req)
            let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
            if (200..<300).contains(status) {
                appLog("uploadAvatar: success", category: "account")
            } else {
                appWarn("uploadAvatar: HTTP \(status)", category: "account")
            }
        } catch {
            appError("uploadAvatar: \(error.localizedDescription)", category: "account")
        }
        avatarImage = image
        saveAvatarLocally(image)
    }

    /// Load avatar from local cache first, then from server. Updates `avatarImage`.
    func loadAvatar(forceRefresh: Bool = false) async {
        if !forceRefresh, let cached = loadAvatarLocally() {
            avatarImage = cached
            appLog("loadAvatar: loaded from local cache", category: "account")
            return
        }
        guard isLoggedIn, let userId = currentUser?.id else { return }
        guard let req = makeBaseRequest("/user/avatar/\(userId)", method: "GET") else { return }
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
            guard (200..<300).contains(status), let img = UIImage(data: data) else {
                appWarn("loadAvatar: HTTP \(status) or invalid image data", category: "account")
                return
            }
            avatarImage = img
            saveAvatarLocally(img)
            appLog("loadAvatar: fetched from server (\(data.count / 1024)KB)", category: "account")
        } catch {
            appWarn("loadAvatar: \(error.localizedDescription)", category: "account")
        }
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
        guard let url = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("user_avatar.jpg") else { return }
        image.jpegData(compressionQuality: 0.8).flatMap { try? $0.write(to: url) }
    }

    private func loadAvatarLocally() -> UIImage? {
        guard let url = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("user_avatar.jpg") else { return nil }
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
        do {
            _ = try await makeRequest(
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
            appLog("logPlay: \"\(song.title)\" \(listenSeconds)s", category: "account")
        } catch {
            appWarn("logPlay: failed for \"\(song.title)\": \(error.localizedDescription)", category: "account")
        }
    }

    /// Pushes the current track/position to the bridge so other surfaces
    /// (e.g. the local Discord Rich Presence daemon) can mirror "now playing"
    /// for this account. Best-effort and silent on failure — this runs on
    /// every play/pause/track-change and periodically during playback, so it
    /// shouldn't spam logs or interrupt playback if the network is down.
    private var playbackStatePushTask: Task<Void, Never>?

    func pushPlaybackState(song: Song?, position: TimeInterval, duration: TimeInterval, isPlaying: Bool) {
        guard isLoggedIn else { return }
        struct Body: Encodable {
            let song_id: String?
            let title: String?
            let artist: String?
            let track_url: String?
            let source: String?
            let position_seconds: Double
            let duration_seconds: Double
            let is_playing: Bool
        }
        let body = Body(
            song_id: song?.id,
            title: song?.title,
            artist: song?.artist.isEmpty == true ? nil : song?.artist,
            track_url: song?.url?.absoluteString,
            source: nil,
            position_seconds: position,
            duration_seconds: duration,
            is_playing: isPlaying
        )
        playbackStatePushTask?.cancel()
        playbackStatePushTask = Task { [weak self] in
            _ = try? await self?.makeRequest("/user/playback-state", method: "PUT", body: body)
        }
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

    private func handleUnauthorized() {
        appWarn("JWT expired or invalid — clearing session", category: "account")
        UserDefaults.standard.removeObject(forKey: Self.tokenKey)
        UserDefaults.standard.removeObject(forKey: Self.userKey)
        token = nil
        currentUser = nil
        isLoggedIn = false
        errorMessage = "Your session expired. Please sign in again."
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
                // Only auto-logout on 401 when the user was already logged in.
                // A 401 on /auth/login means wrong password — not an expired token.
                if isLoggedIn && path != "/auth/login" {
                    handleUnauthorized()
                }
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
