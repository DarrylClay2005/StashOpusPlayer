import SwiftUI

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
