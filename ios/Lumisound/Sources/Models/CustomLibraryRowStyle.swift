import SwiftUI
import UIKit

/// A user-created song row/grid-cell style — mirrors `CustomNowPlayingStyle`'s
/// approach: pure data, interpreted at runtime by `CustomLibraryRowView` and
/// `CustomLibraryGridCellView`, rather than a hand-written view per style like
/// the 4 built-in `SongCardStyle` cases.
struct CustomLibraryRowStyle: Codable, Identifiable, Equatable {
    var id: String = UUID().uuidString
    var name: String = "My Row Style"
    var iconName: String = "list.bullet.rectangle"

    enum ArtworkShape: String, Codable, CaseIterable, Identifiable {
        case square, rounded, circle
        var id: String { rawValue }
        var label: String {
            switch self {
            case .square:  return "Square"
            case .rounded: return "Rounded"
            case .circle:  return "Circle"
            }
        }
    }
    var artworkShape: ArtworkShape = .rounded
    var artworkCornerRadius: Double = 8   // ignored when artworkShape != .rounded
    var artworkSize: Double = 44          // 28...72, used in row layout only

    enum Layout: String, Codable, CaseIterable, Identifiable {
        case row, card
        var id: String { rawValue }
        var label: String { self == .row ? "Flat Row" : "Elevated Card" }
    }
    var layout: Layout = .row

    enum Density: String, Codable, CaseIterable, Identifiable {
        case tight, normal, spacious
        var id: String { rawValue }
        var label: String {
            switch self {
            case .tight:    return "Tight"
            case .normal:   return "Normal"
            case .spacious: return "Spacious"
            }
        }
        var verticalPadding: CGFloat {
            switch self {
            case .tight:    return 2
            case .normal:   return 6
            case .spacious: return 12
            }
        }
        var spacing: CGFloat {
            switch self {
            case .tight:    return 8
            case .normal:   return 12
            case .spacious: return 16
            }
        }
    }
    var density: Density = .normal

    enum TitleWeight: String, Codable, CaseIterable, Identifiable {
        case regular, medium, semibold, bold
        var id: String { rawValue }
        var label: String {
            switch self {
            case .regular:  return "Regular"
            case .medium:   return "Medium"
            case .semibold: return "Semibold"
            case .bold:     return "Bold"
            }
        }
        var fontWeight: Font.Weight {
            switch self {
            case .regular:  return .regular
            case .medium:   return .medium
            case .semibold: return .semibold
            case .bold:     return .bold
            }
        }
    }
    var titleWeight: TitleWeight = .regular

    var showSubtitle: Bool = true
    var showDuration: Bool = true
    var showDivider: Bool = false

    enum AccentUsage: String, Codable, CaseIterable, Identifiable {
        case textOnly, backgroundTint, border
        var id: String { rawValue }
        var label: String {
            switch self {
            case .textOnly:       return "Title Text Only"
            case .backgroundTint: return "Background Tint"
            case .border:         return "Border Outline"
            }
        }
    }
    var accentUsage: AccentUsage = .textOnly

    // MARK: - Expanded per-element control
    //
    // Everything below is additive to the original fields above — all have
    // defaults that reproduce the original look exactly, so existing saved
    // styles (decoded from before these fields existed) behave unchanged.

    // MARK: Colors
    //
    // Stored as `NSKeyedArchiver`-encoded `Data` (same approach as
    // `AppTheme.dynamicAccent`'s persisted accent color) rather than a hex
    // string, so any `Color`/`UIColor` — including ones with alpha or a
    // dynamic light/dark variant — round-trips exactly. `nil` means "use the
    // theme default", preserved as the out-of-the-box behavior.
    var customAccentColorData: Data?
    var customTitleColorData: Data?
    var customSubtitleColorData: Data?
    var customBackgroundColorData: Data?

    /// Accent used for the "now playing" highlight (title color / background
    /// tint / border, depending on `accentUsage`). Falls back to the app's
    /// global dynamic accent when unset.
    var accentColor: Color {
        get { Self.decodeColor(customAccentColorData) ?? AppTheme.dynamicAccent }
        set { customAccentColorData = Self.encodeColor(newValue) }
    }

    /// Base title text color when the row is *not* the now-playing track.
    /// Falls back to the theme's primary text color when unset.
    var titleColor: Color {
        get { Self.decodeColor(customTitleColorData) ?? AppTheme.textPrimary }
        set { customTitleColorData = Self.encodeColor(newValue) }
    }

    /// Subtitle/duration text color. Falls back to the theme's secondary
    /// text color when unset.
    var subtitleColor: Color {
        get { Self.decodeColor(customSubtitleColorData) ?? AppTheme.textSecondary }
        set { customSubtitleColorData = Self.encodeColor(newValue) }
    }

    /// Base fill behind a card-layout row / grid cell (before any now-playing
    /// accent tint is layered on top). Falls back to the theme's surface
    /// color when unset.
    var backgroundColor: Color {
        get { Self.decodeColor(customBackgroundColorData) ?? AppTheme.elevatedSurface }
        set { customBackgroundColorData = Self.encodeColor(newValue) }
    }

    var hasCustomAccentColor: Bool { customAccentColorData != nil }
    var hasCustomTitleColor: Bool { customTitleColorData != nil }
    var hasCustomSubtitleColor: Bool { customSubtitleColorData != nil }
    var hasCustomBackgroundColor: Bool { customBackgroundColorData != nil }

    static func encodeColor(_ color: Color) -> Data? {
        try? NSKeyedArchiver.archivedData(withRootObject: UIColor(color), requiringSecureCoding: true)
    }

    static func decodeColor(_ data: Data?) -> Color? {
        guard let data,
              let uiColor = try? NSKeyedUnarchiver.unarchivedObject(ofClass: UIColor.self, from: data)
        else { return nil }
        return Color(uiColor)
    }

    // MARK: Background treatment
    //
    // Every field below this point is backed by an `Optional` stored
    // property with a computed non-optional accessor providing the default —
    // NOT a non-optional stored property with a default *initializer*
    // value. Swift's synthesized `Decodable` only consults a property's
    // default when it's `Optional` (via `decodeIfPresent`); a non-optional
    // stored property's default is only used by the memberwise initializer,
    // never by decoding. Since `CustomLibraryRowStyle` relies entirely on
    // synthesized `Codable` (no custom `init(from:)`), a non-optional field
    // added here would make every *already-saved* style on a user's device
    // fail to decode the moment this ships (the whole array, not just this
    // style — see `CustomLibraryStyleStore.load()`'s `try?`). Optional +
    // computed default is what keeps old saved data intact.

    enum BackgroundTreatment: String, Codable, CaseIterable, Identifiable {
        case flat, frostedGlass, gradient
        var id: String { rawValue }
        var label: String {
            switch self {
            case .flat:         return "Flat Color"
            case .frostedGlass: return "Frosted Glass"
            case .gradient:     return "Gradient"
            }
        }
    }
    var backgroundTreatmentRaw: String?
    var backgroundTreatment: BackgroundTreatment {
        get { backgroundTreatmentRaw.flatMap(BackgroundTreatment.init(rawValue:)) ?? .flat }
        set { backgroundTreatmentRaw = newValue.rawValue }
    }

    /// Opacity multiplier applied to whichever background treatment is
    /// active — lets a card blend into the surrounding gallery background
    /// instead of always being fully opaque.
    var backgroundOpacityStored: Double?
    var backgroundOpacity: Double {   // 0...1
        get { backgroundOpacityStored ?? 1.0 }
        set { backgroundOpacityStored = newValue }
    }

    // MARK: Corner radii

    /// Corner radius for the card-layout row background / grid-cell
    /// background — distinct from `artworkCornerRadius`, which only applies
    /// to the artwork thumbnail itself. Ignored by `.row` layout (flat rows
    /// have no card shape to round).
    var cardCornerRadiusStored: Double?
    var cardCornerRadius: Double {   // 0...28
        get { cardCornerRadiusStored ?? 14 }
        set { cardCornerRadiusStored = newValue }
    }

    // MARK: Typography

    /// Point size for the title line. The built-in default (17) matches
    /// SwiftUI's `.body` text style exactly, so an unedited style looks
    /// identical to before this field existed.
    var titleFontSizeStored: Double?
    var titleFontSize: Double {   // 13...24
        get { titleFontSizeStored ?? 17 }
        set { titleFontSizeStored = newValue }
    }

    /// Point size for the subtitle/duration line. 12 matches `.caption`.
    var subtitleFontSizeStored: Double?
    var subtitleFontSize: Double {   // 9...18
        get { subtitleFontSizeStored ?? 12 }
        set { subtitleFontSizeStored = newValue }
    }

    /// Extra letter-spacing (tracking) applied to the title, in points.
    /// 0 reproduces default `Text` kerning exactly.
    var titleLetterSpacingStored: Double?
    var titleLetterSpacing: Double {   // -1...4
        get { titleLetterSpacingStored ?? 0 }
        set { titleLetterSpacingStored = newValue }
    }

    // MARK: Spacing

    /// Extra horizontal inset applied around the whole row/card, on top of
    /// whatever the parent list/grid already applies — lets a style "float"
    /// its cards inward without needing a custom density preset for just
    /// that one dimension.
    var horizontalInsetStored: Double?
    var horizontalInset: Double {   // 0...24
        get { horizontalInsetStored ?? 0 }
        set { horizontalInsetStored = newValue }
    }
}

/// Local persistence for custom library row styles (UserDefaults-backed),
/// mirroring `CustomStyleStore`'s shape. No server sync — purely a
/// per-device visual preference, same as the built-in card style selection.
@MainActor
final class CustomLibraryStyleStore: ObservableObject {
    static let shared = CustomLibraryStyleStore()

    @Published private(set) var styles: [CustomLibraryRowStyle] = []

    private let key = "customLibraryRowStyles.v1"

    private init() { load() }

    func add(_ style: CustomLibraryRowStyle) {
        styles.append(style)
        save()
    }

    func update(_ style: CustomLibraryRowStyle) {
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

    func style(withID id: String) -> CustomLibraryRowStyle? {
        styles.first { $0.id == id }
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: key) else { return }
        if let decoded = try? JSONDecoder().decode([CustomLibraryRowStyle].self, from: data) {
            styles = decoded
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(styles) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}

/// Which built-in `SongCardStyle` cases the user has hidden from their picker
/// (Feature: per-user remove/add of library row styles). Stored separately
/// from the styles themselves, mirroring `HiddenStylesStore`.
@MainActor
final class HiddenCardStylesStore: ObservableObject {
    static let shared = HiddenCardStylesStore()

    @Published private(set) var hiddenRawValues: Set<String> = []

    private let key = "hiddenLibraryCardStyles.v1"

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
