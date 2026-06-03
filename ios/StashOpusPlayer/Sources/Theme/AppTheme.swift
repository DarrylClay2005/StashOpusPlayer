import SwiftUI
import UIKit

// MARK: - AppTheme

enum AppTheme {

    // MARK: Static Color Palette

    static let background       = Color(red: 0.176, green: 0.216, blue: 0.282)
    static let surface          = Color(red: 0.290, green: 0.333, blue: 0.408)
    static let elevatedSurface  = Color(red: 0.353, green: 0.420, blue: 0.490)
    static let accent           = Color(red: 0.925, green: 0.251, blue: 0.478)
    static let accentSoft       = Color(red: 0.957, green: 0.561, blue: 0.694)
    static let textPrimary      = Color(red: 0.969, green: 0.980, blue: 0.988)
    static let textSecondary    = Color(red: 0.796, green: 0.835, blue: 0.878)
    static let warning          = Color(red: 0.965, green: 0.678, blue: 0.333)
    static let success          = Color(red: 0.408, green: 0.827, blue: 0.569)
    static let error            = Color(red: 0.988, green: 0.506, blue: 0.506)

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
            requiringSecureCoding: false
        ) {
            UserDefaults.standard.set(data, forKey: "accent_color_data")
        }
    }

    /// Resets the saved accent color so `dynamicAccent` returns the default pink.
    static func resetAccentColor() {
        UserDefaults.standard.removeObject(forKey: "accent_color_data")
    }
}

// MARK: - Font Helpers

extension AppTheme {
    static func headlineFont(size: CGFloat = 17) -> Font {
        .system(size: size, weight: .semibold, design: .default)
    }

    static func bodyFont(size: CGFloat = 15) -> Font {
        .system(size: size, weight: .regular, design: .default)
    }

    static func monoFont(size: CGFloat = 12) -> Font {
        .system(size: size, weight: .regular, design: .monospaced)
    }
}

// MARK: - View Modifiers

extension View {
    /// Applies the standard full-screen dark background with primary text color.
    func appScreenBackground() -> some View {
        self
            .background(AppTheme.background.ignoresSafeArea())
            .foregroundStyle(AppTheme.textPrimary)
    }

    /// Applies the standard rounded panel surface style.
    func panelStyle() -> some View {
        self
            .padding(14)
            .background(
                AppTheme.surface,
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
    }
}
