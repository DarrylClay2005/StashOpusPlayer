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
    @Published var shuffleIntervalSeconds: Double = 30.0
    @Published var animation: BackgroundAnimation = .fade
    @Published var opacity: Double = 0.35
    @Published var isBlurred: Bool = true

    // MARK: Private

    private var shuffleTimer: Timer?

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
    }

    // MARK: Image Management

    func addImages(_ newImages: [UIImage]) {
        images.append(contentsOf: newImages)
    }

    func removeImage(at index: Int) {
        guard images.indices.contains(index) else { return }
        images.remove(at: index)
        // Keep currentIndex in bounds
        if images.isEmpty {
            currentIndex = 0
        } else if currentIndex >= images.count {
            currentIndex = images.count - 1
        }
    }

    func clearAll() {
        images.removeAll()
        currentIndex = 0
    }

    // MARK: Shuffle Control

    func startShuffling() {
        shuffleTimer?.invalidate()
        guard isEnabled, images.count > 1 else { return }
        shuffleTimer = Timer.scheduledTimer(withTimeInterval: shuffleIntervalSeconds, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.advance()
            }
        }
    }

    func stopShuffling() {
        shuffleTimer?.invalidate()
        shuffleTimer = nil
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

        // If enabled was saved as true but there are no images (images are not persisted), disable.
        if isEnabled, images.isEmpty {
            isEnabled = false
        }
    }
}
