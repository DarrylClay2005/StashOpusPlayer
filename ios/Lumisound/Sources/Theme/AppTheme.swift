import SwiftUI
import UIKit

// MARK: - AppTheme

enum AppTheme {

    // MARK: Static Color Palette

    /// Base palette values for the `.default` background theme — kept as the
    /// literal fallback so `background`/`surface`/`elevatedSurface` below
    /// preserve the exact look every existing install already has.
    static let accent           = Color(red: 0.925, green: 0.251, blue: 0.478)
    static let accentSoft       = Color(red: 0.957, green: 0.561, blue: 0.694)
    static let textPrimary      = Color(red: 0.969, green: 0.980, blue: 0.988)
    static let textSecondary    = Color(red: 0.796, green: 0.835, blue: 0.878)
    static let warning          = Color(red: 0.965, green: 0.678, blue: 0.333)
    static let success          = Color(red: 0.408, green: 0.827, blue: 0.569)
    static let error            = Color(red: 0.988, green: 0.506, blue: 0.506)

    // MARK: Background Theme

    /// Which cohesive background/surface color set is active. `background`/
    /// `surface`/`elevatedSurface` below all read through this, so changing
    /// it takes effect everywhere those three colors are used without
    /// touching any other call site.
    static var backgroundTheme: AppBackgroundTheme {
        if let raw = UserDefaults.standard.string(forKey: "app_background_theme"),
           let theme = AppBackgroundTheme(rawValue: raw) {
            return theme
        }
        return .default
    }

    static func saveBackgroundTheme(_ theme: AppBackgroundTheme) {
        UserDefaults.standard.set(theme.rawValue, forKey: "app_background_theme")
    }

    static func resetBackgroundTheme() {
        UserDefaults.standard.removeObject(forKey: "app_background_theme")
    }

    static var background: Color { backgroundTheme.background }
    static var surface: Color { backgroundTheme.surface }
    static var elevatedSurface: Color { backgroundTheme.elevatedSurface }

    // MARK: Dynamic Accent

    /// Reads a user-saved accent color from UserDefaults.
    /// Falls back to the default pink `accent` if nothing is stored.
    static var dynamicAccent: Color {
        if let data = UserDefaults.standard.data(forKey: "accent_color_data"),
           let uiColor = try? NSKeyedUnarchiver.unarchivedObject(ofClass: UIColor.self, from: data) {
            return Color(uiColor)
        }
        return accent
    }

    /// Persists a new accent color selection to UserDefaults.
    static func saveAccentColor(_ color: Color) {
        let uiColor = UIColor(color)
        if let data = try? NSKeyedArchiver.archivedData(
            withRootObject: uiColor,
            requiringSecureCoding: true
        ) {
            UserDefaults.standard.set(data, forKey: "accent_color_data")
        }
    }

    /// Resets the saved accent color so `dynamicAccent` returns the default pink.
    static func resetAccentColor() {
        UserDefaults.standard.removeObject(forKey: "accent_color_data")
    }

    // MARK: Dynamic Accent — Secondary (gradient pairing)

    /// Second color used wherever the accent is rendered as a gradient
    /// (the mini-player's play button and progress fill, the launch
    /// screen's halo/equalizer, etc.) instead of a flat fill. Defaults to
    /// `accentSoft` — the exact color those gradients already used — so
    /// nothing changes visually until a user picks a custom secondary color.
    static var dynamicAccentSecondary: Color {
        if let data = UserDefaults.standard.data(forKey: "accent_secondary_color_data"),
           let uiColor = try? NSKeyedUnarchiver.unarchivedObject(ofClass: UIColor.self, from: data) {
            return Color(uiColor)
        }
        return accentSoft
    }

    static func saveAccentSecondaryColor(_ color: Color) {
        let uiColor = UIColor(color)
        if let data = try? NSKeyedArchiver.archivedData(
            withRootObject: uiColor,
            requiringSecureCoding: true
        ) {
            UserDefaults.standard.set(data, forKey: "accent_secondary_color_data")
        }
    }

    static func resetAccentSecondaryColor() {
        UserDefaults.standard.removeObject(forKey: "accent_secondary_color_data")
    }

    /// Convenience gradient combining `dynamicAccent` → `dynamicAccentSecondary`.
    static var dynamicAccentGradient: LinearGradient {
        LinearGradient(colors: [dynamicAccent, dynamicAccentSecondary], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

// MARK: - AppBackgroundTheme

/// Cohesive background/surface color presets. `.default` reproduces the
/// app's original fixed colors exactly, so existing installs look unchanged
/// until they pick a different theme.
enum AppBackgroundTheme: String, CaseIterable, Identifiable, Codable {
    case `default`
    case trueBlack
    case midnightBlue
    case deepPurple
    case forest

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .default:     return "Default"
        case .trueBlack:   return "True Black"
        case .midnightBlue: return "Midnight Blue"
        case .deepPurple:  return "Deep Purple"
        case .forest:      return "Forest"
        }
    }

    var background: Color {
        switch self {
        case .default:      return Color(red: 0.176, green: 0.216, blue: 0.282)
        case .trueBlack:    return Color(red: 0.02,  green: 0.02,  blue: 0.03)
        case .midnightBlue: return Color(red: 0.05,  green: 0.08,  blue: 0.18)
        case .deepPurple:   return Color(red: 0.14,  green: 0.08,  blue: 0.20)
        case .forest:       return Color(red: 0.10,  green: 0.16,  blue: 0.14)
        }
    }

    var surface: Color {
        switch self {
        case .default:      return Color(red: 0.290, green: 0.333, blue: 0.408)
        case .trueBlack:    return Color(red: 0.12,  green: 0.12,  blue: 0.14)
        case .midnightBlue: return Color(red: 0.10,  green: 0.15,  blue: 0.28)
        case .deepPurple:   return Color(red: 0.24,  green: 0.14,  blue: 0.32)
        case .forest:       return Color(red: 0.18,  green: 0.26,  blue: 0.22)
        }
    }

    var elevatedSurface: Color {
        switch self {
        case .default:      return Color(red: 0.353, green: 0.420, blue: 0.490)
        case .trueBlack:    return Color(red: 0.18,  green: 0.18,  blue: 0.21)
        case .midnightBlue: return Color(red: 0.14,  green: 0.20,  blue: 0.36)
        case .deepPurple:   return Color(red: 0.32,  green: 0.20,  blue: 0.42)
        case .forest:       return Color(red: 0.24,  green: 0.34,  blue: 0.28)
        }
    }
}

// MARK: - AppFontStyle

enum AppFontStyle: String, CaseIterable, Identifiable, Codable {
    case system
    case rounded
    case serif
    case monospacedDisplay

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system:            return "System"
        case .rounded:           return "Rounded"
        case .serif:             return "Serif"
        case .monospacedDisplay: return "Monospaced"
        }
    }

    var design: Font.Design {
        switch self {
        case .system:            return .default
        case .rounded:           return .rounded
        case .serif:             return .serif
        case .monospacedDisplay: return .monospaced
        }
    }
}

// MARK: - Font Helpers

extension AppTheme {
    /// Which `Font.Design` `headlineFont`/`bodyFont` render with. `monoFont`
    /// deliberately does NOT follow this — it's used for numeric/tabular
    /// displays (durations, BPM, dB values) where actual monospacing is
    /// functionally important, not just decorative.
    static var fontStyle: AppFontStyle {
        if let raw = UserDefaults.standard.string(forKey: "app_font_style"),
           let style = AppFontStyle(rawValue: raw) {
            return style
        }
        return .system
    }

    static func saveFontStyle(_ style: AppFontStyle) {
        UserDefaults.standard.set(style.rawValue, forKey: "app_font_style")
    }

    static func resetFontStyle() {
        UserDefaults.standard.removeObject(forKey: "app_font_style")
    }

    static func headlineFont(size: CGFloat = 17) -> Font {
        .system(size: size, weight: .semibold, design: fontStyle.design)
    }

    static func bodyFont(size: CGFloat = 15) -> Font {
        .system(size: size, weight: .regular, design: fontStyle.design)
    }

    static func monoFont(size: CGFloat = 12) -> Font {
        .system(size: size, weight: .regular, design: .monospaced)
    }
}

// MARK: - View Modifiers

extension View {
    /// Applies the standard primary text color.
    /// Background is intentionally omitted here so that GalleryBackgroundView
    /// (rendered in ContentView's ZStack behind the TabView) can show through.
    /// Views that need an opaque background on top of the gallery (e.g. sheets,
    /// standalone NavigationStack roots) must set .background(AppTheme.background
    /// .ignoresSafeArea()) themselves.
    func appScreenBackground() -> some View {
        self
            .foregroundStyle(AppTheme.textPrimary)
    }

    /// Applies the standard rounded panel surface style.
    /// Panel opacity is controlled by the "panel_opacity" UserDefaults key (set in AppearanceView).
    func panelStyle() -> some View {
        modifier(PanelStyleModifier())
    }
}

/// Panel background look — the standard flat, opacity-controlled surface
/// tint, or a frosted-glass (`.ultraThinMaterial`) treatment with a light
/// tint on top. Applies to the 8 Now Playing sub-panels that use `panelStyle()`.
enum PanelMaterialStyle: String, CaseIterable, Identifiable, Codable {
    case solid
    case frostedGlass

    var id: String { rawValue }
    var displayName: String { self == .solid ? "Solid" : "Frosted Glass" }
}

extension AppTheme {
    static var panelMaterialStyle: PanelMaterialStyle {
        if let raw = UserDefaults.standard.string(forKey: "panel_material_style"),
           let style = PanelMaterialStyle(rawValue: raw) {
            return style
        }
        return .solid
    }

    static func savePanelMaterialStyle(_ style: PanelMaterialStyle) {
        UserDefaults.standard.set(style.rawValue, forKey: "panel_material_style")
    }
}

private struct PanelStyleModifier: ViewModifier {
    @AppStorage("panel_opacity") private var opacity: Double = 1.0
    @AppStorage("panel_material_style") private var materialStyleRaw: String = PanelMaterialStyle.solid.rawValue

    private var isFrostedGlass: Bool {
        PanelMaterialStyle(rawValue: materialStyleRaw) == .frostedGlass
    }

    func body(content: Content) -> some View {
        if isFrostedGlass {
            content
                .padding(14)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .background(AppTheme.surface.opacity(opacity * 0.35), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        } else {
            content
                .padding(14)
                .background(
                    AppTheme.surface.opacity(opacity),
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                )
        }
    }
}
