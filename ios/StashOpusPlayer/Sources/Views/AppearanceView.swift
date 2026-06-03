import SwiftUI
import UIKit

// MARK: - AppearanceView

struct AppearanceView: View {

    // MARK: State

    /// Tracks the current custom color chosen in the ColorPicker.
    @State private var customColor: Color = AppTheme.dynamicAccent

    /// Forces the view to re-render after a preset or reset tap so the preview
    /// and swatch highlights update immediately.
    @State private var refreshToken = UUID()

    // MARK: Preset Swatches

    private struct PresetSwatch: Identifiable {
        let id = UUID()
        let name: String
        let color: Color
    }

    private let presetSwatches: [PresetSwatch] = [
        .init(name: "Pink",   color: Color(red: 0.925, green: 0.251, blue: 0.478)),
        .init(name: "Blue",   color: Color(red: 0.255, green: 0.533, blue: 0.961)),
        .init(name: "Purple", color: Color(red: 0.588, green: 0.290, blue: 0.878)),
        .init(name: "Green",  color: Color(red: 0.208, green: 0.780, blue: 0.349)),
        .init(name: "Orange", color: Color(red: 0.988, green: 0.549, blue: 0.133)),
        .init(name: "Yellow", color: Color(red: 0.988, green: 0.820, blue: 0.200)),
    ]

    // MARK: Body

    var body: some View {
        List {

            // MARK: — Preview Section
            Section {
                accentPreviewRow
            } header: {
                Text("Preview")
                    .font(AppTheme.bodyFont())
                    .foregroundStyle(AppTheme.textSecondary)
            }

            // MARK: — Quick-Pick Presets
            Section {
                presetSwatchGrid
            } header: {
                Text("Quick Picks")
                    .font(AppTheme.bodyFont())
                    .foregroundStyle(AppTheme.textSecondary)
            }

            // MARK: — Custom Color Picker
            Section {
                ColorPicker("Custom Color", selection: $customColor, supportsOpacity: false)
                    .foregroundStyle(AppTheme.textPrimary)
                    .onChange(of: customColor) { newColor in
                        AppTheme.saveAccentColor(newColor)
                        refreshToken = UUID()
                    }
            } header: {
                Text("Custom")
                    .font(AppTheme.bodyFont())
                    .foregroundStyle(AppTheme.textSecondary)
            }

            // MARK: — Reset
            Section {
                Button(role: .destructive) {
                    AppTheme.resetAccentColor()
                    customColor = AppTheme.accent
                    refreshToken = UUID()
                } label: {
                    HStack {
                        Image(systemName: "arrow.counterclockwise")
                        Text("Reset to Default")
                    }
                }
                .foregroundStyle(AppTheme.accent)
            }
        }
        .id(refreshToken)
        .scrollContentBackground(.hidden)
        .background(Color.clear.ignoresSafeArea())
        .navigationTitle("Appearance")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            customColor = AppTheme.dynamicAccent
        }
    }

    // MARK: — Subviews

    /// A mini preview card showing how the current accent looks on UI elements.
    private var accentPreviewRow: some View {
        let current = AppTheme.dynamicAccent

        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                // Swatch circle
                Circle()
                    .fill(current)
                    .frame(width: 44, height: 44)
                    .shadow(color: current.opacity(0.5), radius: 6, x: 0, y: 3)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Accent Color")
                        .font(AppTheme.headlineFont())
                        .foregroundStyle(AppTheme.textPrimary)
                    Text("Used in tabs, toggles, and highlights")
                        .font(AppTheme.bodyFont(size: 13))
                        .foregroundStyle(AppTheme.textSecondary)
                }
                Spacer()
            }

            // Sample UI elements
            HStack(spacing: 10) {
                // Sample play button
                Image(systemName: "play.circle.fill")
                    .font(.title)
                    .foregroundStyle(current)

                // Sample toggle (rendered manually for preview purposes)
                Capsule()
                    .fill(current)
                    .frame(width: 44, height: 26)
                    .overlay(
                        Circle()
                            .fill(Color.white)
                            .frame(width: 22, height: 22)
                            .offset(x: 9)
                    )

                // Sample label
                Text("Now Playing")
                    .font(AppTheme.bodyFont(size: 13))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(current.opacity(0.2), in: Capsule())
                    .foregroundStyle(current)

                Spacer()
            }
        }
        .padding(.vertical, 6)
        .listRowBackground(AppTheme.surface)
    }

    /// A grid of quick-pick color swatches.
    private var presetSwatchGrid: some View {
        let current = AppTheme.dynamicAccent

        return HStack(spacing: 16) {
            ForEach(presetSwatches) { swatch in
                Button {
                    AppTheme.saveAccentColor(swatch.color)
                    customColor = swatch.color
                    refreshToken = UUID()
                } label: {
                    VStack(spacing: 4) {
                        ZStack {
                            Circle()
                                .fill(swatch.color)
                                .frame(width: 40, height: 40)
                                .shadow(color: swatch.color.opacity(0.4), radius: 4, x: 0, y: 2)

                            // Checkmark if this swatch matches the active accent
                            if colorMatches(swatch.color, current) {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundStyle(.white)
                            }
                        }

                        Text(swatch.name)
                            .font(AppTheme.monoFont(size: 10))
                            .foregroundStyle(AppTheme.textSecondary)
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .listRowBackground(AppTheme.surface)
    }

    // MARK: Helpers

    /// Compares two Colors by converting both to UIColor components.
    /// Avoids false negatives from minor floating-point differences.
    private func colorMatches(_ a: Color, _ b: Color) -> Bool {
        let ua = UIColor(a), ub = UIColor(b)
        var (r1, g1, b1, a1): (CGFloat, CGFloat, CGFloat, CGFloat) = (0, 0, 0, 0)
        var (r2, g2, b2, a2): (CGFloat, CGFloat, CGFloat, CGFloat) = (0, 0, 0, 0)
        ua.getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
        ub.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
        let threshold: CGFloat = 0.02
        return abs(r1 - r2) < threshold
            && abs(g1 - g2) < threshold
            && abs(b1 - b2) < threshold
    }
}
