import SwiftUI
import UIKit

// MARK: - AppearanceView

struct AppearanceView: View {

    // MARK: State

    /// Used only to source a representative song for the card-style live preview.
    @EnvironmentObject private var library: LibraryManager
    /// Used to push the accent color change to the server immediately — without
    /// this, a color picked here only syncs the next time favorites/playlists/
    /// audio settings change (see `AccountService.pullSync`'s theme-color comment),
    /// so a fresh install on another device could miss it entirely.
    @EnvironmentObject private var account: AccountService

    @State private var customColor: Color = AppTheme.dynamicAccent
    @State private var refreshToken = UUID()

    @AppStorage("panel_opacity")             private var panelOpacity: Double = 1.0
    @AppStorage("nowPlaying_artworkStyle")   private var artworkStyleRaw: String = NowPlayingArtworkStyle.vinylDisc.rawValue
    @AppStorage("nowPlaying_seekerStyle")    private var seekerStyleRaw: String  = SeekerStyle.waveform.rawValue
    @AppStorage("library_cardStyle")         private var cardStyleRaw: String    = SongCardStyle.compact.rawValue

    // MARK: Preset Swatches

    private struct PresetSwatch: Identifiable {
        let id = UUID()
        let name: String
        let color: Color
    }

    private let presetSwatches: [PresetSwatch] = [
        .init(name: "Pink",    color: Color(red: 0.925, green: 0.251, blue: 0.478)),
        .init(name: "Blue",    color: Color(red: 0.255, green: 0.533, blue: 0.961)),
        .init(name: "Purple",  color: Color(red: 0.588, green: 0.290, blue: 0.878)),
        .init(name: "Green",   color: Color(red: 0.208, green: 0.780, blue: 0.349)),
        .init(name: "Orange",  color: Color(red: 0.988, green: 0.549, blue: 0.133)),
        .init(name: "Yellow",  color: Color(red: 0.988, green: 0.820, blue: 0.200)),
        .init(name: "Teal",    color: Color(red: 0.180, green: 0.757, blue: 0.729)),
        .init(name: "Red",     color: Color(red: 0.961, green: 0.220, blue: 0.220)),
    ]

    // MARK: Body

    var body: some View {
        List {

            // MARK: — Preview
            Section {
                accentPreviewRow
            } header: {
                sectionHeader("Preview")
            }

            // MARK: — Quick-Pick Presets
            Section {
                presetSwatchGrid
            } header: {
                sectionHeader("Quick Picks")
            }

            // MARK: — Custom Color Picker
            Section {
                ColorPicker("Custom Color", selection: $customColor, supportsOpacity: false)
                    .foregroundStyle(AppTheme.textPrimary)
                    .onChange(of: customColor) { newColor in
                        AppTheme.saveAccentColor(newColor)
                        refreshToken = UUID()
                        account.schedulePush(library: library)
                    }
                    .listRowBackground(AppTheme.surface)
            } header: {
                sectionHeader("Custom")
            }

            // MARK: — Player Style Defaults
            Section {
                artworkStylePicker
                seekerStylePicker
            } header: {
                sectionHeader("Player Style Defaults")
            } footer: {
                Text("These set the starting style for new sessions. You can also switch styles live in the Now Playing screen.")
                    .font(AppTheme.bodyFont(size: 12))
                    .foregroundStyle(AppTheme.textSecondary)
            }

            // MARK: — Song Card Style
            Section {
                cardStylePicker
            } header: {
                sectionHeader("Song Cards")
            } footer: {
                Text("Changes how song rows look across Library, Queue, Favorites, Playlists, and Artist screens.")
                    .font(AppTheme.bodyFont(size: 12))
                    .foregroundStyle(AppTheme.textSecondary)
            }

            // MARK: — Interface
            Section {
                panelOpacityRow
            } header: {
                sectionHeader("Interface")
            } footer: {
                Text("Controls how opaque the playback panels appear. Lower values give a more transparent look.")
                    .font(AppTheme.bodyFont(size: 12))
                    .foregroundStyle(AppTheme.textSecondary)
            }

            // MARK: — Reset
            Section {
                Button(role: .destructive) {
                    AppTheme.resetAccentColor()
                    customColor = AppTheme.accent
                    panelOpacity = 1.0
                    refreshToken = UUID()
                    account.schedulePush(library: library)
                } label: {
                    HStack {
                        Image(systemName: "arrow.counterclockwise")
                        Text("Reset to Default")
                    }
                }
                .foregroundStyle(AppTheme.dynamicAccent)
                .listRowBackground(AppTheme.surface)
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

    private var accentPreviewRow: some View {
        let current = AppTheme.dynamicAccent

        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
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

            HStack(spacing: 10) {
                Image(systemName: "play.circle.fill")
                    .font(.title)
                    .foregroundStyle(current)

                Capsule()
                    .fill(current)
                    .frame(width: 44, height: 26)
                    .overlay(
                        Circle()
                            .fill(Color.white)
                            .frame(width: 22, height: 22)
                            .offset(x: 9)
                    )

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

    private var presetSwatchGrid: some View {
        let current = AppTheme.dynamicAccent

        return LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 4),
            spacing: 14
        ) {
            ForEach(presetSwatches) { swatch in
                Button {
                    AppTheme.saveAccentColor(swatch.color)
                    customColor = swatch.color
                    refreshToken = UUID()
                    account.schedulePush(library: library)
                } label: {
                    VStack(spacing: 4) {
                        ZStack {
                            Circle()
                                .fill(swatch.color)
                                .frame(width: 44, height: 44)
                                .shadow(color: swatch.color.opacity(0.4), radius: 4, x: 0, y: 2)

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
        .listRowBackground(AppTheme.surface)
    }

    private var artworkStylePicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Default Artwork Style")
                .font(AppTheme.bodyFont())
                .foregroundStyle(AppTheme.textPrimary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(NowPlayingArtworkStyle.allCases) { style in
                        Button {
                            artworkStyleRaw = style.rawValue
                        } label: {
                            VStack(spacing: 4) {
                                Image(systemName: style.iconName)
                                    .font(.system(size: 13, weight: .medium))
                                Text(style.displayName)
                                    .font(.system(size: 10, weight: .medium))
                            }
                            .foregroundStyle(artworkStyleRaw == style.rawValue ? .white : AppTheme.textSecondary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .background(
                                artworkStyleRaw == style.rawValue ? AppTheme.dynamicAccent : AppTheme.elevatedSurface,
                                in: RoundedRectangle(cornerRadius: 9, style: .continuous)
                            )
                        }
                        .buttonStyle(.plain)
                        .animation(.easeInOut(duration: 0.15), value: artworkStyleRaw)
                    }
                }
                .padding(.bottom, 2)
            }
        }
        .padding(.vertical, 6)
        .listRowBackground(AppTheme.surface)
    }

    private var cardStylePicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Song Row Style")
                .font(AppTheme.bodyFont())
                .foregroundStyle(AppTheme.textPrimary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(SongCardStyle.allCases) { style in
                        Button {
                            cardStyleRaw = style.rawValue
                        } label: {
                            VStack(spacing: 4) {
                                Image(systemName: style.iconName)
                                    .font(.system(size: 13, weight: .medium))
                                Text(style.displayName)
                                    .font(.system(size: 10, weight: .medium))
                            }
                            .foregroundStyle(cardStyleRaw == style.rawValue ? .white : AppTheme.textSecondary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .background(
                                cardStyleRaw == style.rawValue ? AppTheme.dynamicAccent : AppTheme.elevatedSurface,
                                in: RoundedRectangle(cornerRadius: 9, style: .continuous)
                            )
                        }
                        .buttonStyle(.plain)
                        .animation(.easeInOut(duration: 0.15), value: cardStyleRaw)
                    }
                }
                .padding(.bottom, 2)
            }

            // Live preview using a representative row in the chosen style.
            if let previewSong = library.allSongs.first {
                SongRow(song: previewSong, isCurrent: false)
                    .id(cardStyleRaw)
                    .padding(.top, 2)
            }
        }
        .padding(.vertical, 6)
        .listRowBackground(AppTheme.surface)
    }

    private var seekerStylePicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Default Seeker Style")
                .font(AppTheme.bodyFont())
                .foregroundStyle(AppTheme.textPrimary)

            HStack(spacing: 8) {
                ForEach(SeekerStyle.allCases) { style in
                    Button {
                        seekerStyleRaw = style.rawValue
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: style.iconName)
                                .font(.system(size: 13, weight: .medium))
                            Text(style.displayName)
                                .font(.system(size: 10, weight: .medium))
                        }
                        .foregroundStyle(seekerStyleRaw == style.rawValue ? .white : AppTheme.textSecondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(
                            seekerStyleRaw == style.rawValue ? AppTheme.dynamicAccent : AppTheme.elevatedSurface,
                            in: RoundedRectangle(cornerRadius: 9, style: .continuous)
                        )
                    }
                    .buttonStyle(.plain)
                    .animation(.easeInOut(duration: 0.15), value: seekerStyleRaw)
                }
                Spacer()
            }
        }
        .padding(.vertical, 6)
        .listRowBackground(AppTheme.surface)
    }

    private var panelOpacityRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Panel Opacity")
                    .font(AppTheme.bodyFont())
                    .foregroundStyle(AppTheme.textPrimary)
                Spacer()
                Text(String(format: "%.0f%%", panelOpacity * 100))
                    .font(AppTheme.monoFont())
                    .foregroundStyle(AppTheme.textSecondary)
                    .monospacedDigit()
            }
            Slider(value: $panelOpacity, in: 0.2...1.0)
                .tint(AppTheme.dynamicAccent)

            // Mini preview panel
            HStack(spacing: 10) {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 16))
                    .foregroundStyle(AppTheme.dynamicAccent)
                Text("Panel preview")
                    .font(AppTheme.bodyFont(size: 13))
                    .foregroundStyle(AppTheme.textPrimary)
            }
            .padding(12)
            .background(
                AppTheme.surface.opacity(panelOpacity),
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
        }
        .padding(.vertical, 6)
        .listRowBackground(AppTheme.surface)
    }

    // MARK: Helpers

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(AppTheme.bodyFont())
            .foregroundStyle(AppTheme.textSecondary)
    }

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
