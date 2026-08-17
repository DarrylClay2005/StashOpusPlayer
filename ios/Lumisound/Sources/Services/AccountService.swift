import Foundation
import SwiftUI
import UIKit

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
    @Published var similarListenerTracks: [TrendingTrack] = []
    @Published var similarListenerCount: Int = 0
    @Published var ariaDailyPick: AriaDailyPick? = nil
    @Published var sessions: [AccountSession] = []
    @Published var stats: AccountStats? = nil
    @Published var achievements: AchievementsData? = nil
    @Published var yearInReview: YearInReview? = nil
    @Published var monthInReview: MonthInReview? = nil
    @Published var adminOverview: AdminOverview? = nil
    @Published var adminDownloadJobs: [AdminDownloadJob] = []
    @Published var adminErrors: [AdminErrorLogEntry] = []
    @Published var adminUsers: [AdminUser] = []
    @Published var hasDateOfBirth: Bool = false
    // Unread notification count for AccountView's badge — @Published (not
    // view-local @State) so it can be refreshed the instant a push arrives
    // while foregrounded (see AppDelegate's willPresent -> refreshUnreadNotificationCount),
    // not just when the view re-appears. Previously this only ever refreshed
    // on `.task` (view first-appear), so a push banner could visibly show
    // while the app was open without the in-app badge count changing until
    // the user navigated away and back — the "needs a tab switch to refresh"
    // pattern.
    @Published var unreadNotificationCount: Int = 0
    // Two-factor auth (TOTP). `pendingTOTPToken` is set by `login()` when the
    // server responds `requires_2fa` instead of a session — LoginView shows a
    // code-entry step and calls `completeTOTPLogin(code:)` while this is set,
    // instead of treating that response as a login failure.
    @Published var pendingTOTPToken: String? = nil
    @Published var isTOTPEnabled: Bool = false

    // MARK: Persisted token
    //
    // Security hardening — moved from plain UserDefaults to the Keychain
    // (see KeychainTokenStore's doc comment for why). The getter migrates
    // any pre-existing UserDefaults-stored token into the Keychain on first
    // read and then scrubs it from UserDefaults, so an already-logged-in
    // user upgrading to this version stays logged in instead of silently
    // losing their session — the old plaintext copy doesn't linger
    // alongside the new Keychain one, which would defeat the point of
    // moving it at all.

    var token: String? {
        get {
            if let migrated = UserDefaults.standard.string(forKey: Self.tokenKey) {
                KeychainTokenStore.set(migrated, account: "auth_token")
                UserDefaults.standard.removeObject(forKey: Self.tokenKey)
                return migrated
            }
            return KeychainTokenStore.get(account: "auth_token")
        }
        set {
            if let newValue {
                KeychainTokenStore.set(newValue, account: "auth_token")
            } else {
                KeychainTokenStore.delete(account: "auth_token")
            }
            // Belt-and-suspenders: guarantees no plaintext copy survives in
            // UserDefaults even if some future code path ever writes
            // through this setter without going through the migration
            // above first.
            UserDefaults.standard.removeObject(forKey: Self.tokenKey)
        }
    }

    // MARK: Debounce state

    var syncDebounceTask: Task<Void, Never>?

    // MARK: Auto-push timer

    var autoPushTimer: Timer?

    func startAutoPushTimer(library: LibraryManager) {
        stopAutoPushTimer()
        autoPushTimer = Timer.scheduledTimer(withTimeInterval: 8 * 60, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.isLoggedIn else { return }
                await self.pushSync(library: library)
                await self.syncLibraryInventory(library: library)
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
            await self.syncLibraryInventory(library: library)
        }
    }

    /// Uploads the set of source ids currently in the on-device library
    /// (Song.sourceTrackID + download-ledger ids whose files are still present)
    /// to the bridge, so server-side dedup (playlist resolve / downloads) knows
    /// what the user already has even though yt-dlp can never see the device's
    /// folders. Replaces the stored snapshot, so deletions are reflected. Cheap
    /// and debounced via the schedulePush path that calls it.
    func syncLibraryInventory(library: LibraryManager) async {
        guard isLoggedIn else { return }
        var ids = Set(library.allSongs.compactMap { $0.sourceTrackID }.filter { !$0.isEmpty })
        let presentFilenames = Set(library.allSongs.compactMap { $0.url?.lastPathComponent })
        for id in DownloadLedgerStore.shared.presentSourceIDs(presentFilenames: presentFilenames) {
            ids.insert(id)
        }
        struct InventoryBody: Encodable { let source_ids: [String] }
        do {
            _ = try await makeRequest("/user/library/inventory", method: "POST",
                                      body: InventoryBody(source_ids: Array(ids)))
            appLog("syncLibraryInventory: uploaded \(ids.count) source id(s)", category: "account")
            // One event per debounced push, not per source id.
            RemoteLogger.log(category: "sync", event: "library_inventory_synced", detail: ["count": ids.count])
        } catch {
            // Same "superseded by a newer debounced call" cancellation as
            // pushSync's identical guard — an expected, routine condition,
            // not a real failure. See AccountService+Sync.swift's pushSync
            // for the full reasoning.
            if (error as? URLError)?.code == .cancelled {
                appLog("syncLibraryInventory superseded by a newer sync (expected)", category: "account")
                return
            }
            appWarn("syncLibraryInventory failed: \(error.localizedDescription)", category: "account")
            RemoteLogger.logError(category: "sync", event: "library_inventory_sync_failed",
                                   message: error.localizedDescription)
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
            // Deliberately NOT gated on `token != nil` here. `currentUser`
            // and the Keychain-backed token are always cleared together --
            // handleUnauthorized()/clearSession() both wipe userKey and the
            // token in the same call, so restoring a cached user from
            // UserDefaults already proves this session was valid as of the
            // last write. Re-checking the Keychain read on every launch
            // (including headless background launches while the device is
            // locked -- see KeychainTokenStore's doc comment) risks a false
            // "no token" read flipping isLoggedIn to false even though the
            // real Keychain item and the server-side session are both still
            // intact, which then persists in this long-lived @StateObject
            // until the next real 401 or explicit logout corrects it -- the
            // exact "randomly logged out on open" bug this fixes. A
            // genuinely revoked/expired session is still caught correctly
            // by the normal 401 handling in
            // AccountService+PrivateHelpers.swift the next time an
            // authenticated request actually goes out.
            isLoggedIn = true
            hasDateOfBirth = user.dateOfBirth != nil
            // Show the cached avatar immediately so the launch screen never
            // flashes the placeholder initial circle for a returning user —
            // `loadAvatar(forceRefresh: true)` (called later, post-pullSync)
            // skips the cache and hits the network, which is too slow for
            // the launch screen's first frame.
            avatarImage = loadAvatarLocally()
        }
        let ts = UserDefaults.standard.double(forKey: Self.lastSyncKey)
        if ts > 0 {
            // Bypass didSet to avoid re-writing the same value on init
            _lastSyncDate = Published(initialValue: Date(timeIntervalSince1970: ts))
        }
        Self.shared = self
    }


    // MARK: Cross-extension stored state (extensions in AccountService+*.swift
    // cannot hold stored properties, so anything they need across calls lives here)

    /// Debounce task mirroring `schedulePush` — folder-structure pushes ride
    /// along on the same 2-second debounce window as the main sync push, since
    /// both are triggered by the same kinds of changes (library rescans/imports).
    var folderBackupDebounceTask: Task<Void, Never>?
    var playbackStatePushTask: Task<Void, Never>?

}

// MARK: - Error types

struct AccountError: LocalizedError {
    let statusCode: Int
    let message: String

    var errorDescription: String? { message }
}

struct APIErrorBody: Decodable {
    let detail: String
}
