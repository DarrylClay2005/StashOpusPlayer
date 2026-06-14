import Foundation
import UIKit
import PhotosUI
import SwiftUI

// MARK: - BackgroundAnimation

enum BackgroundAnimation: String, CaseIterable, Codable, Identifiable {
    case fade       = "Fade"
    case slideLeft  = "Slide Left"
    case slideUp    = "Slide Up"
    case zoomIn     = "Zoom In"
    case zoomOut    = "Zoom Out"
    case flip       = "Flip"
    case blur       = "Blur In"
    case none       = "Cut"

    var id: String { rawValue }
    var displayName: String { rawValue }
    var sfSymbol: String {
        switch self {
        case .fade:      return "circle.lefthalf.filled"
        case .slideLeft: return "arrow.left"
        case .slideUp:   return "arrow.up"
        case .zoomIn:    return "magnifyingglass.circle.fill"
        case .zoomOut:   return "minus.magnifyingglass"
        case .flip:      return "rotate.3d"
        case .blur:      return "aqi.medium"
        case .none:      return "scissors"
        }
    }
}

// MARK: - BackgroundService

@MainActor
final class BackgroundService: ObservableObject {

    // MARK: Published State

    @Published var isEnabled: Bool = false {
        didSet { saveSettings() }
    }
    @Published var images: [UIImage] = []
    @Published var currentIndex: Int = 0
    @Published var shuffleIntervalSeconds: Double = 30.0 {
        didSet {
            saveSettings()
            if isActive { startShuffling() }  // restart with new interval
        }
    }
    @Published var animation: BackgroundAnimation = .fade {
        didSet { saveSettings() }
    }
    @Published var opacity: Double = 0.35 {
        didSet { saveSettings() }
    }
    /// Gaussian blur radius applied to the background image, 0-40. Replaces
    /// the old on/off `isBlurred` toggle — the Help screen has always
    /// described this as "a blur slider" with a 20-40 range, but the control
    /// was actually a binary switch with a fixed radius of 16 (8 in the
    /// settings preview). `loadSettings()` migrates any previously-saved
    /// `isBlurred` bool into an equivalent radius (16 or 0) on first load.
    @Published var blurRadius: Double = 16.0 {
        didSet { saveSettings() }
    }

    /// True when the shuffle timer is running. Stored property so iOS backgrounding
    /// doesn't silently invalidate it without us knowing.
    @Published private(set) var isActive: Bool = false

    // MARK: Private

    private var shuffleTimer: Timer?
    // Tracks every timer added to the RunLoop so none are orphaned on rapid addImages calls.
    private var allTimers: [Timer] = []
    private var foregroundObserver: NSObjectProtocol?

    /// Debounce task for automatic cloud gallery backup — mirrors
    /// `AccountService.schedulePush`'s 2-second debounce so rapid successive
    /// `addImages`/`removeImage`/`clearAll` calls (e.g. picking 20 photos at
    /// once) only trigger one upload pass.
    private var cloudSyncTask: Task<Void, Never>?

    /// Set once per app launch the first time a cloud gallery restore has been
    /// attempted, so `loadSettings()` (which can run more than once, e.g. after
    /// `willEnterForegroundNotification`) doesn't repeatedly hit the network.
    private var didAttemptCloudRestore = false

    // MARK: Init — register for foreground notification

    init() {
        foregroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.isEnabled, !self.images.isEmpty else { return }
                if !self.isActive { self.startShuffling() }
            }
        }
    }

    deinit {
        if let foregroundObserver {
            NotificationCenter.default.removeObserver(foregroundObserver)
        }
    }

    // MARK: Interval Presets

    static let intervalPresets: [(label: String, seconds: Double)] = [
        ("5 sec", 5), ("10 sec", 10), ("15 sec", 15), ("30 sec", 30),
        ("1 min", 60), ("2 min", 120), ("5 min", 300)
    ]

    // MARK: UserDefaults Keys

    private enum Keys {
        static let isEnabled             = "bgService.isEnabled"
        static let shuffleInterval       = "bgService.shuffleInterval"
        static let animation             = "bgService.animation"
        static let opacity               = "bgService.opacity"
        static let blurRadius            = "bgService.blurRadius"
        /// Legacy on/off blur switch — read once during migration in `loadSettings()`.
        static let isBlurredLegacy       = "bgService.isBlurred"
        static let imageFilenames        = "bg_image_filenames_v1"  // [String] of filenames
    }

    // MARK: Disk Storage Directory

    private var imageStorageDir: URL {
        // Documents is effectively always available on iOS, but crashing the whole
        // app over a missing directory for a background-image feature is too harsh —
        // fall back to the (always-available) temp directory and degrade gracefully.
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return docs.appendingPathComponent("BackgroundImages", isDirectory: true)
    }

    // MARK: Image Management

    func addImages(_ newImages: [UIImage]) {
        images.append(contentsOf: newImages)
        saveImagesToDisk()
        if !isEnabled {
            isEnabled = true
            saveSettings()
        }
        // Always (re)start to ensure a single clean timer — startShuffling() kills all orphans first.
        currentIndex = 0
        startShuffling()
        objectWillChange.send()
        appLog("addImages: gallery ready (images=\(images.count), active=\(isActive))", category: "background")
        scheduleCloudGallerySync(newImages: newImages)
    }

    func removeImage(at index: Int) {
        guard images.indices.contains(index) else { return }
        images.remove(at: index)
        if images.isEmpty {
            currentIndex = 0
            stopShuffling()
        } else if currentIndex >= images.count {
            currentIndex = images.count - 1
        }
        saveImagesToDisk()
        scheduleCloudGallerySync()
    }

    func clearAll() {
        images.removeAll()
        currentIndex = 0
        saveImagesToDisk()
        scheduleCloudGallerySync()
    }

    // MARK: Cloud Gallery Backup (automatic, all logged-in users, no opt-in)

    /// Schedules an automatic cloud backup of the gallery 2 seconds after the
    /// last image-list mutation. When `newImages` is non-nil, only those new
    /// images are uploaded (existing cloud copies are left alone); otherwise
    /// (removal/clear) the full local gallery is re-synced — any cloud image
    /// no longer present locally is deleted so cloud and device stay in sync.
    private func scheduleCloudGallerySync(newImages: [UIImage]? = nil) {
        guard AccountService.shared?.isLoggedIn == true,
              let streaming = StreamingService.shared else { return }

        cloudSyncTask?.cancel()
        cloudSyncTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
            guard let self, !Task.isCancelled,
                  let token = AccountService.shared?.token, !token.isEmpty
            else { return }

            if let newImages, !newImages.isEmpty {
                // Upload-only path: just push the newly-added images.
                for (offset, image) in newImages.enumerated() {
                    guard !Task.isCancelled else { return }
                    let order = self.images.count - newImages.count + offset
                    do {
                        _ = try await streaming.uploadGalleryImage(image, token: token, displayOrder: order)
                    } catch {
                        appWarn("BackgroundService: cloud gallery upload failed: \(error.localizedDescription)", category: "background")
                    }
                }
                appLog("BackgroundService: auto-uploaded \(newImages.count) new gallery image(s) to cloud", category: "background")
                return
            }

            // Removal/clear path: reconcile the cloud gallery to match the local
            // image count by deleting the trailing cloud entries beyond what's
            // left locally. We don't have a stable per-image cloud ID locally,
            // so this is a best-effort prune rather than a precise diff.
            do {
                let cloud = try await streaming.fetchGalleryImages(token: token)
                let excess = cloud.count - self.images.count
                if excess > 0 {
                    let toDelete = cloud.sorted { $0.displayOrder > $1.displayOrder }.prefix(excess)
                    for image in toDelete {
                        guard !Task.isCancelled else { return }
                        try? await streaming.deleteGalleryImage(id: image.id, token: token)
                    }
                    appLog("BackgroundService: pruned \(excess) cloud gallery image(s) after local removal", category: "background")
                }
            } catch {
                appWarn("BackgroundService: cloud gallery reconcile failed: \(error.localizedDescription)", category: "background")
            }
        }
    }

    /// Called on first login after a fresh install/reinstall (when the local
    /// gallery is empty but the user has cloud-backed-up images) to redownload
    /// and repopulate the local gallery automatically — no opt-in toggle.
    /// Safe to call repeatedly; only does work once per app launch and only
    /// when there are no local images yet (so it never clobbers images the
    /// user has already picked on this device).
    func restoreGalleryFromCloudIfNeeded() {
        guard !didAttemptCloudRestore else { return }
        guard images.isEmpty else {
            didAttemptCloudRestore = true
            return
        }
        guard AccountService.shared?.isLoggedIn == true,
              let token = AccountService.shared?.token, !token.isEmpty,
              let streaming = StreamingService.shared
        else { return }

        didAttemptCloudRestore = true
        Task { [weak self] in
            guard let self else { return }
            do {
                let cloud = try await streaming.fetchGalleryImages(token: token)
                guard !cloud.isEmpty else { return }
                var restored: [UIImage] = []
                for entry in cloud.sorted(by: { $0.displayOrder < $1.displayOrder }) {
                    if let img = await streaming.fetchGalleryImageData(entry, token: token) {
                        restored.append(img)
                    }
                }
                guard !restored.isEmpty else { return }
                // Append directly to `images`/disk rather than via `addImages` —
                // avoids re-triggering an upload of the images we just downloaded.
                self.images = restored
                self.saveImagesToDisk()
                if !self.isEnabled {
                    self.isEnabled = true
                    self.saveSettings()
                }
                self.currentIndex = 0
                self.startShuffling()
                appLog("restoreGalleryFromCloudIfNeeded: restored \(restored.count) gallery image(s) from cloud", category: "background")
                ToastCenter.shared.show("Restored \(restored.count) background image\(restored.count == 1 ? "" : "s") from your account", category: .success, icon: "icloud.and.arrow.down")
            } catch {
                appWarn("restoreGalleryFromCloudIfNeeded: \(error.localizedDescription)", category: "background")
            }
        }
    }

    // MARK: Disk Persistence

    private func loadImagesFromDisk() {
        let defaults = UserDefaults.standard
        guard let filenames = defaults.stringArray(forKey: Keys.imageFilenames) else {
            appLog("loadImagesFromDisk: no saved filenames — scanning disk for orphaned images", category: "background")
            rebuildManifestFromDisk()
            return
        }
        let fm = FileManager.default
        var loaded: [UIImage] = []
        for name in filenames {
            let path = imageStorageDir.appendingPathComponent(name)
            if let data = try? Data(contentsOf: path), let img = UIImage(data: data) {
                loaded.append(img)
            } else {
                appWarn("loadImagesFromDisk: failed to load \(name)", category: "background")
            }
        }
        images = loaded
        appLog("loadImagesFromDisk: loaded \(loaded.count)/\(filenames.count) images", category: "background")
        if isEnabled && !images.isEmpty {
            startShuffling()
        }
    }

    /// Scans imageStorageDir for JPEG/PNG files and rebuilds the UserDefaults manifest.
    /// Called after a reinstall when the manifest key is missing but image files still exist.
    private func rebuildManifestFromDisk() {
        let fm = FileManager.default
        guard fm.fileExists(atPath: imageStorageDir.path) else { return }
        let imageExts: Set<String> = ["jpg", "jpeg", "png", "heic"]
        let files = (try? fm.contentsOfDirectory(atPath: imageStorageDir.path)) ?? []
        let imageFiles = files
            .filter { imageExts.contains(($0 as NSString).pathExtension.lowercased()) }
            .sorted()
        guard !imageFiles.isEmpty else { return }
        var loaded: [UIImage] = []
        for name in imageFiles {
            let path = imageStorageDir.appendingPathComponent(name)
            if let data = try? Data(contentsOf: path), let img = UIImage(data: data) {
                loaded.append(img)
            }
        }
        guard !loaded.isEmpty else { return }
        images = loaded
        UserDefaults.standard.set(imageFiles, forKey: Keys.imageFilenames)
        appLog("rebuildManifestFromDisk: restored \(loaded.count) image(s) from disk", category: "background")
        if isEnabled { startShuffling() }
    }

    private func saveImagesToDisk() {
        let fm = FileManager.default
        try? fm.createDirectory(at: imageStorageDir, withIntermediateDirectories: true)

        // Capture existing files before writing new ones so we can clean up orphans
        let existing = (try? fm.contentsOfDirectory(atPath: imageStorageDir.path)) ?? []

        var filenames: [String] = []
        for (i, img) in images.enumerated() {
            let name = "bg_\(i)_\(Int(Date().timeIntervalSince1970)).jpg"
            let path = imageStorageDir.appendingPathComponent(name)
            if let data = img.jpegData(compressionQuality: 0.8) {
                try? data.write(to: path)
                filenames.append(name)
            }
        }

        // Remove old images not in the new set
        for file in existing {
            if !filenames.contains(file) {
                try? fm.removeItem(at: imageStorageDir.appendingPathComponent(file))
            }
        }

        UserDefaults.standard.set(filenames, forKey: Keys.imageFilenames)
    }

    // MARK: Shuffle Control

    func startShuffling() {
        // Kill every tracked timer — prevents orphaned timers from rapid addImages calls.
        allTimers.forEach { $0.invalidate() }
        allTimers.removeAll()
        shuffleTimer = nil

        guard isEnabled, !images.isEmpty else {
            isActive = false
            appLog("startShuffling: skipped (enabled=\(isEnabled) images=\(images.count))", category: "background")
            return
        }
        let timer = Timer(timeInterval: shuffleIntervalSeconds, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.advance() }
        }
        RunLoop.main.add(timer, forMode: .common)
        shuffleTimer = timer
        allTimers = [timer]
        isActive = true
        appLog("startShuffling: timer started interval=\(shuffleIntervalSeconds)s images=\(images.count)", category: "background")
    }

    func stopShuffling() {
        allTimers.forEach { $0.invalidate() }
        allTimers.removeAll()
        shuffleTimer = nil
        isActive = false
        appLog("stopShuffling: timer stopped", category: "background")
    }

    func nextImage() {
        advance()
        // Reset the timer so the next automatic advance starts fresh
        if isEnabled { startShuffling() }
    }

    // MARK: Private Advance

    private func advance() {
        guard !images.isEmpty else { return }
        let next = (currentIndex + 1) % images.count
        appLog("advance: index → \(next)/\(images.count)", category: "background")
        // Cap the crossfade so it always finishes before the next shuffle
        // tick fires — at the fastest preset (5s) an 8s transition would
        // still be mid-animation when the next `advance()` lands, causing
        // the incoming image to jump/cut instead of completing its fade.
        let duration = min(8.0, shuffleIntervalSeconds * 0.6)
        withAnimation(.easeInOut(duration: duration)) {
            currentIndex = next
        }
    }

    // MARK: Persistence

    func saveSettings() {
        let defaults = UserDefaults.standard
        defaults.set(isEnabled, forKey: Keys.isEnabled)
        defaults.set(shuffleIntervalSeconds, forKey: Keys.shuffleInterval)
        defaults.set(animation.rawValue, forKey: Keys.animation)
        defaults.set(opacity, forKey: Keys.opacity)
        defaults.set(blurRadius, forKey: Keys.blurRadius)
    }

    func loadSettings() {
        let defaults = UserDefaults.standard

        // isEnabled — default false when key absent
        isEnabled = defaults.bool(forKey: Keys.isEnabled)

        if let interval = defaults.object(forKey: Keys.shuffleInterval) as? Double {
            shuffleIntervalSeconds = interval
        }

        if let rawAnim = defaults.string(forKey: Keys.animation),
           let anim = BackgroundAnimation(rawValue: rawAnim) {
            animation = anim
        }

        if let savedOpacity = defaults.object(forKey: Keys.opacity) as? Double {
            opacity = savedOpacity
        }

        if let savedRadius = defaults.object(forKey: Keys.blurRadius) as? Double {
            blurRadius = savedRadius
        } else if let legacyBlur = defaults.object(forKey: Keys.isBlurredLegacy) as? Bool {
            // One-time migration from the old on/off toggle.
            blurRadius = legacyBlur ? 16.0 : 0.0
            defaults.removeObject(forKey: Keys.isBlurredLegacy)
            defaults.set(blurRadius, forKey: Keys.blurRadius)
        }

        // Load persisted images from disk; this also starts shuffling if enabled
        loadImagesFromDisk()

        // If enabled was saved as true but no images could be loaded, disable.
        if isEnabled, images.isEmpty {
            isEnabled = false
        }
        appLog("loadSettings: enabled=\(isEnabled) images=\(images.count) interval=\(shuffleIntervalSeconds)s active=\(isActive)", category: "background")

        // Automatic cloud restore for returning users on a fresh install: if no
        // local gallery images exist but the account has cloud-backed-up ones,
        // redownload them. No-ops for logged-out users or users with local images.
        restoreGalleryFromCloudIfNeeded()
    }
}
