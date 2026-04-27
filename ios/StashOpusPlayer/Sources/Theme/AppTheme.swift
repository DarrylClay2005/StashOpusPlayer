import SwiftUI

enum AppTheme {
    static let background = Color(red: 0.176, green: 0.216, blue: 0.282)
    static let surface = Color(red: 0.290, green: 0.333, blue: 0.408)
    static let elevatedSurface = Color(red: 0.353, green: 0.420, blue: 0.490)
    static let accent = Color(red: 0.925, green: 0.251, blue: 0.478)
    static let accentSoft = Color(red: 0.957, green: 0.561, blue: 0.694)
    static let textPrimary = Color(red: 0.969, green: 0.980, blue: 0.988)
    static let textSecondary = Color(red: 0.796, green: 0.835, blue: 0.878)
    static let warning = Color(red: 0.965, green: 0.678, blue: 0.333)
    static let success = Color(red: 0.408, green: 0.827, blue: 0.569)
    static let error = Color(red: 0.988, green: 0.506, blue: 0.506)
}

extension View {
    func appScreenBackground() -> some View {
        self
            .background(AppTheme.background.ignoresSafeArea())
            .foregroundStyle(AppTheme.textPrimary)
    }

    func panelStyle() -> some View {
        self
            .padding(14)
            .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}
