import Foundation
import SwiftUI

// MARK: - Curated profile accent palette
//
// Discord-style two-tone profile accenting: a "main" color drives primary
// chrome on the profile screen (header background wash, name text), a "sub"
// color drives secondary accents (bio border, pinned-track highlights). Both
// are picked from this fixed, curated palette rather than a free-form color
// picker — the bridge validates against this exact set server-side
// (`_CURATED_ACCENT_HEXES` in main.py) and rejects anything else, so a
// malformed/arbitrary hex can never make a profile's own chrome unreadable.
// Keep this list's hex values in sync with the server's set if it ever changes.
enum SocialAccentPalette {
    struct Swatch: Identifiable, Equatable {
        let name: String
        let hex: String
        let color: Color
        var id: String { hex }
    }

    static let swatches: [Swatch] = [
        Swatch(name: "Rose",     hex: "#F13D7A", color: Color(hex: "#F13D7A")),
        Swatch(name: "Coral",    hex: "#FF8A5C", color: Color(hex: "#FF8A5C")),
        Swatch(name: "Amber",    hex: "#FFC94D", color: Color(hex: "#FFC94D")),
        Swatch(name: "Mint",     hex: "#8CE99A", color: Color(hex: "#8CE99A")),
        Swatch(name: "Teal",     hex: "#4FD1C5", color: Color(hex: "#4FD1C5")),
        Swatch(name: "Sky",      hex: "#4DA3FF", color: Color(hex: "#4DA3FF")),
        Swatch(name: "Indigo",   hex: "#7C6CF0", color: Color(hex: "#7C6CF0")),
        Swatch(name: "Lavender", hex: "#C08CFF", color: Color(hex: "#C08CFF")),
        Swatch(name: "Pink",     hex: "#FF6FB1", color: Color(hex: "#FF6FB1")),
        Swatch(name: "Aqua",     hex: "#6EE7DE", color: Color(hex: "#6EE7DE")),
        Swatch(name: "Red",      hex: "#F76E6E", color: Color(hex: "#F76E6E")),
        Swatch(name: "Slate",    hex: "#B0B8C4", color: Color(hex: "#B0B8C4")),
        Swatch(name: "White",    hex: "#FFFFFF", color: Color(hex: "#FFFFFF")),
        Swatch(name: "Charcoal", hex: "#2B2F38", color: Color(hex: "#2B2F38")),
    ]

    static func color(for hex: String?) -> Color? {
        guard let hex else { return nil }
        return swatches.first { $0.hex.caseInsensitiveCompare(hex) == .orderedSame }?.color
    }
}

extension Color {
    /// Minimal hex initializer for the curated palette above — not a
    /// general-purpose parser (no alpha, no shorthand 3-digit forms), since
    /// every value it's ever fed comes from the fixed `swatches` list.
    init(hex: String) {
        let stripped = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        let s = stripped.count == 6 ? stripped : "000000"
        var value: UInt64 = 0
        Scanner(string: s).scanHexInt64(&value)
        let r = Double((value >> 16) & 0xFF) / 255
        let g = Double((value >> 8) & 0xFF) / 255
        let b = Double(value & 0xFF) / 255
        self = Color(red: r, green: g, blue: b)
    }
}

/// A row of tappable swatches for picking either the main or sub profile
/// accent color from the curated palette.
struct AccentColorPickerView: View {
    let title: String
    @Binding var selectedHex: String?

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 5)

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(AppTheme.bodyFont(size: 13))
                .foregroundStyle(AppTheme.textSecondary)

            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(SocialAccentPalette.swatches) { swatch in
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                            selectedHex = swatch.hex
                        }
                    } label: {
                        Circle()
                            .fill(swatch.color)
                            .frame(width: 36, height: 36)
                            .overlay(
                                Circle()
                                    .stroke(.white.opacity(0.25), lineWidth: 1)
                            )
                            .overlay {
                                if selectedHex?.caseInsensitiveCompare(swatch.hex) == .orderedSame {
                                    Circle()
                                        .stroke(AppTheme.textPrimary, lineWidth: 2)
                                        .padding(-3)
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 12, weight: .bold))
                                        .foregroundStyle(swatch.hex == "#FFFFFF" ? .black : .white)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(swatch.name)
                }
            }
        }
    }
}
