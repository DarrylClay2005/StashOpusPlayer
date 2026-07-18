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
/// `CustomStyleArtworkView` (artwork-card-scoped rendering) and, since the
/// 2026-07 Now Playing redesign, `NowPlayingScreenStyle` in
/// `NowPlayingStyle.swift` (whole-screen typography/layout/background
/// rendering). This trades the visual specificity of a bespoke view for
/// genuine end-user customizability: any combination of the options below,
/// saved, and reused.
///
/// 2026-07 redesign note: every field below marked "New in the 2026-07
/// redesign" was added additively — existing saved styles (persisted as
/// JSON via `CustomStyleStore`) predate these fields entirely. `init(from:)`
/// below uses `decodeIfPresent(default:)` for every single field (old and
/// new) specifically so a pre-redesign saved style decodes cleanly instead
/// of silently failing `JSONDecoder` and getting dropped by
/// `CustomStyleStore.load()`.
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
        case none, glowRing, particles, sweep, bars, waveform, blobs, confetti, vinylGrooves, lightRays
        var id: String { rawValue }
        var label: String {
            switch self {
            case .none:         return "None"
            case .glowRing:     return "Glow Ring"
            case .particles:    return "Floating Particles"
            case .sweep:        return "Light Sweep"
            case .bars:         return "Equalizer Bars"
            case .waveform:     return "Live Waveform"
            case .blobs:        return "Color Blobs"
            case .confetti:     return "Confetti"
            case .vinylGrooves: return "Vinyl Grooves"
            case .lightRays:    return "Light Rays"
            }
        }
        var iconName: String {
            switch self {
            case .none:         return "circle.dashed"
            case .glowRing:     return "circle.dotted"
            case .particles:    return "sparkles"
            case .sweep:        return "dot.radiowaves.left.and.right"
            case .bars:         return "chart.bar.fill"
            case .waveform:     return "waveform"
            case .blobs:        return "drop.circle.fill"
            case .confetti:     return "party.popper.fill"
            case .vinylGrooves: return "circle.circle"
            case .lightRays:    return "sun.max.fill"
            }
        }
    }
    var decoration: Decoration = .glowRing

    enum CoverAnimation: String, Codable, CaseIterable, Identifiable {
        case none, float, pulse, rotate, sway, bounce, tilt
        var id: String { rawValue }
        var label: String {
            switch self {
            case .none:   return "None (Static)"
            case .float:  return "Float"
            case .pulse:  return "Pulse"
            case .rotate: return "Rotate"
            case .sway:   return "Sway"
            case .bounce: return "Bounce"
            case .tilt:   return "Tilt"
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

    // MARK: - New in the 2026-07 redesign: whole-screen background treatment

    /// Extra Gaussian blur applied to the *entire Now Playing screen's*
    /// background layer (behind artwork/controls) — independent of any
    /// blur the artwork card's own background already does. 0...40.
    var backgroundBlurRadius: Double = 0
    /// A black scrim over the whole-screen background, for text legibility
    /// against busy custom images/video. 0 (none) ... 0.6 (heavy).
    var backgroundDimming: Double = 0
    /// Overlays a soft animated `MeshGradient` (iOS 18+; falls back to an
    /// animated linear gradient on older OS versions) across the whole
    /// screen background, using `backgroundColor1`/`backgroundColor2` (or
    /// the extracted palette, if `dynamicColorExtraction` is on).
    var useMeshGradient: Bool = false
    /// When true, `backgroundColor1`/`backgroundColor2` and (when
    /// `accentSource == .palette`) the accent color are replaced at runtime
    /// by colors sampled live from the current track's artwork via
    /// `ArtworkColorExtractor` — a "dynamic from artwork" toggle that
    /// applies independently of `backgroundKind`.
    var dynamicColorExtraction: Bool = false

    enum CustomBackgroundMedia: String, Codable, CaseIterable, Identifiable {
        case none, image, video
        var id: String { rawValue }
        var label: String {
            switch self {
            case .none:  return "None"
            case .image: return "Custom Image"
            case .video: return "Custom Video"
            }
        }
    }
    /// Whole-screen background media, layered beneath everything else.
    /// The actual file lives under `CustomStyleMediaStore.directoryURL`;
    /// these store only its filename (never raw `Data` in the style
    /// itself, which would bloat every encode/decode of `CustomStyleStore`'s
    /// whole array).
    var customBackgroundMedia: CustomBackgroundMedia = .none
    var customBackgroundImageFilename: String?
    var customBackgroundVideoFilename: String?
    /// Opacity of the custom image/video layer, so it can be blended
    /// subtly behind controls rather than fully replacing the background.
    var customBackgroundOpacity: Double = 1.0

    // MARK: - New in the 2026-07 redesign: typography

    enum FontChoice: String, Codable, CaseIterable, Identifiable {
        case system, rounded, serif, monospaced
        var id: String { rawValue }
        var label: String {
            switch self {
            case .system:     return "System"
            case .rounded:    return "Rounded"
            case .serif:      return "Serif"
            case .monospaced: return "Monospaced"
            }
        }
        var design: Font.Design {
            switch self {
            case .system:     return .default
            case .rounded:    return .rounded
            case .serif:      return .serif
            case .monospaced: return .monospaced
            }
        }
        func font(weight: Font.Weight, size: CGFloat) -> Font {
            .system(size: size, weight: weight, design: design)
        }
    }

    enum FontWeightOption: String, Codable, CaseIterable, Identifiable {
        case regular, medium, semibold, bold, heavy, black
        var id: String { rawValue }
        var label: String { rawValue.capitalized }
        var weight: Font.Weight {
            switch self {
            case .regular:  return .regular
            case .medium:   return .medium
            case .semibold: return .semibold
            case .bold:     return .bold
            case .heavy:    return .heavy
            case .black:    return .black
            }
        }
    }

    var titleFontChoice: FontChoice = .system
    var titleFontWeight: FontWeightOption = .bold
    /// Multiplies the title's base size (22pt). 0.7...1.6.
    var titleFontScale: Double = 1.0
    var artistFontChoice: FontChoice = .system
    var artistFontWeight: FontWeightOption = .regular
    /// Multiplies the artist row's base size (17pt). 0.7...1.6.
    var artistFontScale: Double = 1.0

    // MARK: - New in the 2026-07 redesign: per-element color overrides

    var titleColorOverrideEnabled: Bool = false
    var titleColor = CodableColor(.white)
    var artistColorOverrideEnabled: Bool = false
    var artistColor = CodableColor(.white)
    /// Overrides the (inactive-state) icon color of secondary transport
    /// buttons (shuffle/prev/next/repeat) — independent of the accent,
    /// which already tints their *active* state.
    var controlsColorOverrideEnabled: Bool = false
    var controlsColor = CodableColor(.white)

    // MARK: - New in the 2026-07 redesign: control layout

    enum TransportControl: String, Codable, CaseIterable, Identifiable {
        case shuffle, previous, playPause, next, repeatControl
        var id: String { rawValue }
        var label: String {
            switch self {
            case .shuffle:       return "Shuffle"
            case .previous:      return "Previous"
            case .playPause:     return "Play / Pause"
            case .next:          return "Next"
            case .repeatControl: return "Repeat"
            }
        }
    }
    /// Left-to-right order the transport row renders its controls in.
    /// `playPause` stays visually centered by `TransportControls`'s layout
    /// regardless of its position in this array — only the *other four*
    /// controls' relative order (and which side of play/pause they fall on)
    /// is actually driven by this list.
    var transportControlOrder: [TransportControl] = TransportControl.allCases
    /// Controls omitted from the transport row entirely. `playPause` is
    /// never allowed in this set — see `CustomNowPlayingStyle.sanitized()`.
    var hiddenTransportControls: Set<TransportControl> = []
    /// Scales every transport button's frame/font size. 0.75...1.35.
    var transportControlScale: Double = 1.0

    enum SpacingDensity: String, Codable, CaseIterable, Identifiable {
        case compact, cozy, spacious
        var id: String { rawValue }
        var label: String { rawValue.capitalized }
        var multiplier: CGFloat {
            switch self {
            case .compact:  return 0.72
            case .cozy:     return 1.0
            case .spacious: return 1.35
            }
        }
    }
    /// Overall vertical rhythm between the Now Playing screen's core
    /// sections (artwork / track info / timeline / transport).
    var sectionSpacingDensity: SpacingDensity = .cozy
    /// Corner radius applied to pills/chips across the screen (style
    /// chips, info chips) — distinct from the artwork cover's own
    /// `cornerRadius`.
    var panelCornerRadius: Double = 10

    /// Guards against a corrupt/hand-edited style hiding every control
    /// (including play/pause) or leaving `transportControlOrder` missing
    /// entries added after the style was first saved (e.g. a style saved
    /// before a new `TransportControl` case existed). Called by
    /// `NowPlayingScreenStyle.resolve` rather than at decode time, so a
    /// still-technically-invalid saved style never crashes — it's just
    /// repaired the next time it's actually rendered.
    func sanitized() -> CustomNowPlayingStyle {
        var copy = self
        copy.hiddenTransportControls.remove(.playPause)
        let known = Set(TransportControl.allCases)
        let existing = Set(copy.transportControlOrder)
        if existing != known {
            // Keep the saved relative order for controls still present,
            // then append any controls the order list is missing.
            copy.transportControlOrder = copy.transportControlOrder.filter { known.contains($0) }
            for control in TransportControl.allCases where !existing.contains(control) {
                copy.transportControlOrder.append(control)
            }
        }
        return copy
    }

    // MARK: - Codable (manual, for additive backward compatibility)

    private enum CodingKeys: String, CodingKey {
        case id, name, iconName
        case backgroundKind, backgroundColor1, backgroundColor2
        case coverShape, cornerRadius, coverSize
        case borderStyle, borderUsesAccent, borderColor
        case shadowStyle
        case decoration
        case coverAnimation, animationSpeed
        case accentSource, customAccentColor
        case backgroundBlurRadius, backgroundDimming, useMeshGradient, dynamicColorExtraction
        case customBackgroundMedia, customBackgroundImageFilename, customBackgroundVideoFilename, customBackgroundOpacity
        case titleFontChoice, titleFontWeight, titleFontScale
        case artistFontChoice, artistFontWeight, artistFontScale
        case titleColorOverrideEnabled, titleColor
        case artistColorOverrideEnabled, artistColor
        case controlsColorOverrideEnabled, controlsColor
        case transportControlOrder, hiddenTransportControls, transportControlScale
        case sectionSpacingDensity, panelCornerRadius
    }

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? "My Style"
        iconName = try c.decodeIfPresent(String.self, forKey: .iconName) ?? "paintpalette.fill"

        backgroundKind = try c.decodeIfPresent(BackgroundKind.self, forKey: .backgroundKind) ?? .ambient
        backgroundColor1 = try c.decodeIfPresent(CodableColor.self, forKey: .backgroundColor1) ?? CodableColor(.indigo)
        backgroundColor2 = try c.decodeIfPresent(CodableColor.self, forKey: .backgroundColor2) ?? CodableColor(.purple)

        coverShape = try c.decodeIfPresent(CoverShape.self, forKey: .coverShape) ?? .rounded
        cornerRadius = try c.decodeIfPresent(Double.self, forKey: .cornerRadius) ?? 20
        coverSize = try c.decodeIfPresent(Double.self, forKey: .coverSize) ?? 200

        borderStyle = try c.decodeIfPresent(BorderStyle.self, forKey: .borderStyle) ?? .thin
        borderUsesAccent = try c.decodeIfPresent(Bool.self, forKey: .borderUsesAccent) ?? true
        borderColor = try c.decodeIfPresent(CodableColor.self, forKey: .borderColor) ?? CodableColor(.white)

        shadowStyle = try c.decodeIfPresent(ShadowStyle.self, forKey: .shadowStyle) ?? .soft
        decoration = try c.decodeIfPresent(Decoration.self, forKey: .decoration) ?? .glowRing
        coverAnimation = try c.decodeIfPresent(CoverAnimation.self, forKey: .coverAnimation) ?? .float
        animationSpeed = try c.decodeIfPresent(Double.self, forKey: .animationSpeed) ?? 1.0

        accentSource = try c.decodeIfPresent(AccentSource.self, forKey: .accentSource) ?? .palette
        customAccentColor = try c.decodeIfPresent(CodableColor.self, forKey: .customAccentColor) ?? CodableColor(.pink)

        backgroundBlurRadius = try c.decodeIfPresent(Double.self, forKey: .backgroundBlurRadius) ?? 0
        backgroundDimming = try c.decodeIfPresent(Double.self, forKey: .backgroundDimming) ?? 0
        useMeshGradient = try c.decodeIfPresent(Bool.self, forKey: .useMeshGradient) ?? false
        dynamicColorExtraction = try c.decodeIfPresent(Bool.self, forKey: .dynamicColorExtraction) ?? false

        customBackgroundMedia = try c.decodeIfPresent(CustomBackgroundMedia.self, forKey: .customBackgroundMedia) ?? .none
        customBackgroundImageFilename = try c.decodeIfPresent(String.self, forKey: .customBackgroundImageFilename)
        customBackgroundVideoFilename = try c.decodeIfPresent(String.self, forKey: .customBackgroundVideoFilename)
        customBackgroundOpacity = try c.decodeIfPresent(Double.self, forKey: .customBackgroundOpacity) ?? 1.0

        titleFontChoice = try c.decodeIfPresent(FontChoice.self, forKey: .titleFontChoice) ?? .system
        titleFontWeight = try c.decodeIfPresent(FontWeightOption.self, forKey: .titleFontWeight) ?? .bold
        titleFontScale = try c.decodeIfPresent(Double.self, forKey: .titleFontScale) ?? 1.0
        artistFontChoice = try c.decodeIfPresent(FontChoice.self, forKey: .artistFontChoice) ?? .system
        artistFontWeight = try c.decodeIfPresent(FontWeightOption.self, forKey: .artistFontWeight) ?? .regular
        artistFontScale = try c.decodeIfPresent(Double.self, forKey: .artistFontScale) ?? 1.0

        titleColorOverrideEnabled = try c.decodeIfPresent(Bool.self, forKey: .titleColorOverrideEnabled) ?? false
        titleColor = try c.decodeIfPresent(CodableColor.self, forKey: .titleColor) ?? CodableColor(.white)
        artistColorOverrideEnabled = try c.decodeIfPresent(Bool.self, forKey: .artistColorOverrideEnabled) ?? false
        artistColor = try c.decodeIfPresent(CodableColor.self, forKey: .artistColor) ?? CodableColor(.white)
        controlsColorOverrideEnabled = try c.decodeIfPresent(Bool.self, forKey: .controlsColorOverrideEnabled) ?? false
        controlsColor = try c.decodeIfPresent(CodableColor.self, forKey: .controlsColor) ?? CodableColor(.white)

        transportControlOrder = try c.decodeIfPresent([TransportControl].self, forKey: .transportControlOrder) ?? TransportControl.allCases
        hiddenTransportControls = try c.decodeIfPresent(Set<TransportControl>.self, forKey: .hiddenTransportControls) ?? []
        transportControlScale = try c.decodeIfPresent(Double.self, forKey: .transportControlScale) ?? 1.0

        sectionSpacingDensity = try c.decodeIfPresent(SpacingDensity.self, forKey: .sectionSpacingDensity) ?? .cozy
        panelCornerRadius = try c.decodeIfPresent(Double.self, forKey: .panelCornerRadius) ?? 10
    }
}

/// On-disk storage for custom-style background media (images/video) picked
/// by the user in `CustomStyleEditorView`. `CustomNowPlayingStyle` itself
/// only stores the filename — keeping raw `Data` out of the model avoids
/// bloating every encode/decode of `CustomStyleStore`'s full style array
/// just to render one style's editor screen.
enum CustomStyleMediaStore {
    static var directoryURL: URL {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("NowPlayingCustomBackgrounds", isDirectory: true)
        if !FileManager.default.fileExists(atPath: base.path) {
            try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        }
        return base
    }

    static func url(for filename: String) -> URL {
        directoryURL.appendingPathComponent(filename)
    }

    /// Writes `data` under a fresh UUID filename and returns it, or `nil` on
    /// a write failure (caller keeps whatever filename — if any — was
    /// already saved on the style).
    @discardableResult
    static func save(data: Data, preferredExtension: String) -> String? {
        let filename = UUID().uuidString + "." + preferredExtension
        do {
            try data.write(to: url(for: filename), options: .atomic)
            return filename
        } catch {
            return nil
        }
    }

    static func delete(filename: String?) {
        guard let filename else { return }
        try? FileManager.default.removeItem(at: url(for: filename))
    }
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
        if let style = styles.first(where: { $0.id == id }) {
            CustomStyleMediaStore.delete(filename: style.customBackgroundImageFilename)
            CustomStyleMediaStore.delete(filename: style.customBackgroundVideoFilename)
        }
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
