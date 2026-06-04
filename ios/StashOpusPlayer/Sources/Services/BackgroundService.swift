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

    @Published var isEnabled: Bool = false
    @Published var images: [UIImage] = []
    @Published var currentIndex: Int = 0
    @Published var shuffleIntervalSeconds: Double = 30.0 {
        didSet {
            saveSettings()
            if isActive { startShuffling() }  // restart with new interval
        }
    }
    @Published var animation: BackgroundAnimation = .fade
    @Published var opacity: Double = 0.35
    @Published var isBlurred: Bool = true

    /// True when the shuffle timer is running. Stored property so iOS backgrounding
    /// doesn't silently invalidate it without us knowing.
    @Published private(set) var isActive: Bool = false

    // MARK: Private

    private var shuffleTimer: Timer?

    // MARK: Init — register for foreground notification

    init() {
        NotificationCenter.default.addObserver(
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
        static let isBlurred             = "bgService.isBlurred"
        static let imageFilenames        = "bg_image_filenames_v1"  // [String] of filenames
    }

    // MARK: Disk Storage Directory

    private var imageStorageDir: URL {
        guard let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            fatalError("Document directory unavailable")
        }
        return docs.appendingPathComponent("BackgroundImages", isDirectory: true)
    }

    // MARK: Image Management

    func addImages(_ newImages: [UIImage]) {
        images.append(contentsOf: newImages)
        saveImagesToDisk()
        // Auto-enable so users don't have to toggle the switch before adding images.
        if !isEnabled {
            isEnabled = true
            saveSettings()
            appLog("addImages: auto-enabled (images=\(images.count))", category: "background")
        }
        if !isActive { startShuffling() }
        currentIndex = 0
        objectWillChange.send()
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
    }

    func clearAll() {
        images.removeAll()
        currentIndex = 0
        saveImagesToDisk()
    }

    // MARK: Disk Persistence

    private func loadImagesFromDisk() {
        let defaults = UserDefaults.standard
        guard let filenames = defaults.stringArray(forKey: Keys.imageFilenames) else {
            appLog("loadImagesFromDisk: no saved filenames", category: "background")
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
        shuffleTimer?.invalidate()
        shuffleTimer = nil
        guard isEnabled, !images.isEmpty else {
            isActive = false
            appLog("startShuffling: skipped (enabled=\(isEnabled) images=\(images.count))", category: "background")
            return
        }
        // Use RunLoop.main + .common mode so the timer fires even while a List/ScrollView
        // is being tracked (default mode timers are suspended during UITrackingRunLoopMode).
        // MainActor.assumeIsolated is safe here because we add to RunLoop.main explicitly.
        let timer = Timer(timeInterval: shuffleIntervalSeconds, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.advance() }
        }
        RunLoop.main.add(timer, forMode: .common)
        shuffleTimer = timer
        isActive = true
        appLog("startShuffling: timer started interval=\(shuffleIntervalSeconds)s images=\(images.count)", category: "background")
    }

    func stopShuffling() {
        shuffleTimer?.invalidate()
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
        currentIndex = (currentIndex + 1) % images.count
        appLog("advance: index → \(currentIndex)/\(images.count)", category: "background")
    }

    // MARK: Persistence

    func saveSettings() {
        let defaults = UserDefaults.standard
        defaults.set(isEnabled, forKey: Keys.isEnabled)
        defaults.set(shuffleIntervalSeconds, forKey: Keys.shuffleInterval)
        defaults.set(animation.rawValue, forKey: Keys.animation)
        defaults.set(opacity, forKey: Keys.opacity)
        defaults.set(isBlurred, forKey: Keys.isBlurred)
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

        if let savedBlur = defaults.object(forKey: Keys.isBlurred) as? Bool {
            isBlurred = savedBlur
        }

        // Load persisted images from disk; this also starts shuffling if enabled
        loadImagesFromDisk()

        // If enabled was saved as true but no images could be loaded, disable.
        if isEnabled, images.isEmpty {
            isEnabled = false
        }
        appLog("loadSettings: enabled=\(isEnabled) images=\(images.count) interval=\(shuffleIntervalSeconds)s active=\(isActive)", category: "background")
    }
}
