import SwiftUI
import UIKit

/// A `Color` that can round-trip through `Codable` — SwiftUI's `Color`
/// itself doesn't conform, so custom Now Playing styles store RGBA
/// components extracted via `UIColor` instead.
struct CodableColor: Codable, Equatable {
    var red: Double
    var green: Double
    var blue: Double
    var opacity: Double

    init(_ color: Color) {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(color).getRed(&r, green: &g, blue: &b, alpha: &a)
        red = Double(r)
        green = Double(g)
        blue = Double(b)
        opacity = Double(a)
    }

    var color: Color {
        Color(red: red, green: green, blue: blue, opacity: opacity)
    }
}

/// A user-created Now Playing style — unlike the 19 built-in
/// `NowPlayingArtworkStyle` cases (each its own hand-written SwiftUI view),
/// a custom style is pure data, interpreted at runtime by
/// `CustomStyleArtworkView`. This trades the visual specificity of a
/// bespoke view for genuine end-user customizability: any combination of
/// background/shape/border/shadow/decoration/animation the picker below
/// offers, saved, and reused.
struct CustomNowPlayingStyle: Codable, Identifiable, Equatable {
    var id: String = UUID().uuidString
    var name: String = "My Style"
    var iconName: String = "paintpalette.fill"

    enum BackgroundKind: String, Codable, CaseIterable, Identifiable {
        case ambient   // soft blurred blobs sampled from the artwork (AmbientArtworkBackground)
        case solid
        case gradient
        case dark
        case light
        var id: String { rawValue }
        var label: String {
            switch self {
            case .ambient:  return "Ambient (from artwork)"
            case .solid:    return "Solid Color"
            case .gradient: return "Gradient"
            case .dark:     return "Dark"
            case .light:    return "Light"
            }
        }
    }
    var backgroundKind: BackgroundKind = .ambient
    var backgroundColor1 = CodableColor(.indigo)
    var backgroundColor2 = CodableColor(.purple)

    enum CoverShape: String, Codable, CaseIterable, Identifiable {
        case rounded, circle
        var id: String { rawValue }
        var label: String { self == .rounded ? "Rounded Rectangle" : "Circle" }
    }
    var coverShape: CoverShape = .rounded
    var cornerRadius: Double = 20       // ignored when coverShape == .circle
    var coverSize: Double = 200         // 120...260

    enum BorderStyle: String, Codable, CaseIterable, Identifiable {
        case none, thin, thick
        var id: String { rawValue }
        var label: String {
            switch self {
            case .none: return "None"
            case .thin: return "Thin"
            case .thick: return "Thick"
            }
        }
        var lineWidth: CGFloat {
            switch self {
            case .none: return 0
            case .thin: return 1.5
            case .thick: return 4
            }
        }
    }
    var borderStyle: BorderStyle = .thin
    var borderUsesAccent: Bool = true
    var borderColor = CodableColor(.white)

    enum ShadowStyle: String, Codable, CaseIterable, Identifiable {
        case none, soft, strong
        var id: String { rawValue }
        var label: String {
            switch self {
            case .none: return "None"
            case .soft: return "Soft"
            case .strong: return "Strong"
            }
        }
    }
    var shadowStyle: ShadowStyle = .soft

    enum Decoration: String, Codable, CaseIterable, Identifiable {
        case none, glowRing, particles, sweep, bars, waveform, blobs
        var id: String { rawValue }
        var label: String {
            switch self {
            case .none:      return "None"
            case .glowRing:  return "Glow Ring"
            case .particles: return "Floating Particles"
            case .sweep:     return "Light Sweep"
            case .bars:      return "Equalizer Bars"
            case .waveform:  return "Live Waveform"
            case .blobs:     return "Color Blobs"
            }
        }
        var iconName: String {
            switch self {
            case .none:      return "circle.dashed"
            case .glowRing:  return "circle.dotted"
            case .particles: return "sparkles"
            case .sweep:     return "dot.radiowaves.left.and.right"
            case .bars:      return "chart.bar.fill"
            case .waveform:  return "waveform"
            case .blobs:     return "drop.circle.fill"
            }
        }
    }
    var decoration: Decoration = .glowRing

    enum CoverAnimation: String, Codable, CaseIterable, Identifiable {
        case none, float, pulse, rotate, sway
        var id: String { rawValue }
        var label: String {
            switch self {
            case .none:   return "None (Static)"
            case .float:  return "Float"
            case .pulse:  return "Pulse"
            case .rotate: return "Rotate"
            case .sway:   return "Sway"
            }
        }
    }
    var coverAnimation: CoverAnimation = .float
    /// 0.5 (slower) ... 2.0 (faster); multiplies the base animation period.
    var animationSpeed: Double = 1.0

    enum AccentSource: String, Codable, CaseIterable, Identifiable {
        case palette, custom
        var id: String { rawValue }
        var label: String { self == .palette ? "From Artwork" : "Custom Color" }
    }
    var accentSource: AccentSource = .palette
    var customAccentColor = CodableColor(.pink)
}

/// Local persistence for custom Now Playing styles (UserDefaults-backed),
/// mirroring `SmartPlaylistStore`'s shape. No server sync — purely a
/// per-device visual preference, same as the built-in style selection.
@MainActor
final class CustomStyleStore: ObservableObject {
    static let shared = CustomStyleStore()

    @Published private(set) var styles: [CustomNowPlayingStyle] = []

    private let key = "customNowPlayingStyles.v1"

    private init() { load() }

    func add(_ style: CustomNowPlayingStyle) {
        styles.append(style)
        save()
    }

    func update(_ style: CustomNowPlayingStyle) {
        guard let idx = styles.firstIndex(where: { $0.id == style.id }) else {
            add(style); return
        }
        styles[idx] = style
        save()
    }

    func remove(id: String) {
        styles.removeAll { $0.id == id }
        save()
    }

    func style(withID id: String) -> CustomNowPlayingStyle? {
        styles.first { $0.id == id }
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: key) else { return }
        if let decoded = try? JSONDecoder().decode([CustomNowPlayingStyle].self, from: data) {
            styles = decoded
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(styles) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}

/// Which built-in `NowPlayingArtworkStyle` cases the user has hidden from
/// their picker (Feature: per-user remove/add of styles). Stored separately
/// from the styles themselves so hiding one is a lightweight preference,
/// not a data-model change to `NowPlayingArtworkStyle`.
@MainActor
final class HiddenStylesStore: ObservableObject {
    static let shared = HiddenStylesStore()

    @Published private(set) var hiddenRawValues: Set<String> = []

    private let key = "hiddenNowPlayingStyles.v1"

    private init() { load() }

    func isHidden(_ rawValue: String) -> Bool { hiddenRawValues.contains(rawValue) }

    func setHidden(_ hidden: Bool, for rawValue: String) {
        if hidden {
            hiddenRawValues.insert(rawValue)
        } else {
            hiddenRawValues.remove(rawValue)
        }
        save()
    }

    private func load() {
        if let saved = UserDefaults.standard.array(forKey: key) as? [String] {
            hiddenRawValues = Set(saved)
        }
    }

    private func save() {
        UserDefaults.standard.set(Array(hiddenRawValues), forKey: key)
    }
}
