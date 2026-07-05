import Foundation
import MediaPlayer
import UIKit

/// Progress snapshot for an in-flight `scanMediaLibrary` run — lets the launch
/// screen show "Scanning 340 of 1,100 songs…" instead of a generic spinner for
/// users with big libraries, where the scan can take many seconds.
struct LibraryScanProgress: Equatable {
    let current: Int
    let total: Int
}

@MainActor
final class LibraryManager: ObservableObject {
    @Published var allSongs: [Song] = []
    @Published var artists: [String] = []
    @Published var albums: [String] = []
    @Published var genres: [String] = []
    @Published var playlists: [Playlist] = []
    @Published var favoriteSongIDs: Set<String> = []
    @Published var isScanning: Bool = false
    @Published var scanProgress: LibraryScanProgress? = nil
    /// Set when `scanMediaLibrary` has bailed out after repeated incomplete
    /// attempts (see the crash-loop guard in `scanMediaLibrary`). Lets the UI
    /// explain *why* the media library never loaded instead of just spinning.
    @Published var scanCrashGuardActive: Bool = false
    @Published var errorMessage: String?
    @Published var lastScanResult: String? = nil

    let persistence: PersistenceService
    let artwork: ArtworkService
    let importer = DocumentImportService()

    // Mirrors `AccountService.shared`/`StreamingService.shared` — gives
    // `BackgroundRefreshService` (invoked directly by iOS via BGTaskScheduler,
    // with no SwiftUI environment access) a way to reach the live library
    // instance for auto-downloading newly-found tracked-playlist tracks.
    static weak var shared: LibraryManager?

    /// Tracks how many scans (media library, local documents, watched folders,
    /// specific-directory) are currently in flight. `isScanning` reflects
    /// whether *any* of them are running, so the launch screen and library UI
    /// stay in "scanning" state for the full duration of a multi-scan launch
    /// instead of flipping to "done" as soon as the first scan finishes.
    var activeScanCount: Int = 0

    func beginScan() {
        activeScanCount += 1
        isScanning = true
    }

    func endScan() {
        activeScanCount = max(0, activeScanCount - 1)
        if activeScanCount == 0 {
            isScanning = false
        }
    }

    var mediaSongs: [Song] = []
    var importedSongs: [Song] = []

    /// Pending debounced rebuild task. Cancelled and replaced on each rapid mutation.
    var pendingRebuildTask: Task<Void, Never>?

    var foregroundObserver: NSObjectProtocol?
    var metadataReenrichTimer: Timer?
    var isReenrichingMetadata = false
    var metadataRefreshTimer: Timer?
    var isRefreshingMetadata = false
    /// Set while `forceMetadataSync` is running, so the Settings button can
    /// show a spinner and avoid overlapping runs.
    @Published var isForcingMetadataSync = false
    /// Rotating cursor into `importedSongs` for `refreshNextMetadataBatch()` —
    /// advances by `metadataRefreshBatchSize` each tick so every track gets
    /// re-read eventually without ever doing a full-library pass in one go.
    var metadataRefreshCursor = 0

    var favoriteSongs: [Song] {
        allSongs.filter { favoriteSongIDs.contains($0.id) }
    }

    init(persistence: PersistenceService = .shared, artwork: ArtworkService = .shared) {
        self.persistence = persistence
        self.artwork = artwork
        Self.shared = self
        favoriteSongIDs = persistence.loadFavorites()
        playlists = persistence.loadPlaylists()
        // Show last session's library immediately — see `loadPersistedSnapshot`.
        // The real scans below always run afterward and overwrite this with
        // fresh data; this just removes the "empty list for several seconds"
        // window for users with big libraries (1000+ songs).
        loadPersistedSnapshot()
        // Re-scan local documents whenever the app returns to the foreground so
        // that files the user added via the Files app while Lumisound was
        // backgrounded are picked up without requiring a manual refresh.
        foregroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.scanLocalDocuments() }
        }
    }

    deinit {
        if let foregroundObserver {
            NotificationCenter.default.removeObserver(foregroundObserver)
        }
        metadataReenrichTimer?.invalidate()
        metadataRefreshTimer?.invalidate()
    }

}
