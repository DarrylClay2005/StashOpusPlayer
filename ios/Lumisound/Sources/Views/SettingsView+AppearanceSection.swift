import MediaPlayer
import SwiftUI

extension SettingsView {

    // MARK: — Appearance Section

    var appearanceSection: some View {
        Section {
            NavigationLink(destination: AppearanceView()) {
                HStack {
                    Label("Appearance", systemImage: "paintbrush")
                        .foregroundStyle(AppTheme.textPrimary)
                    Spacer()
                    // Current accent preview swatch
                    Circle()
                        .fill(AppTheme.dynamicAccent)
                        .frame(width: 22, height: 22)
                        .shadow(color: AppTheme.dynamicAccent.opacity(0.4), radius: 4, x: 0, y: 2)
                }
            }
            NavigationLink(destination: BackgroundSettingsView()) {
                Label("Gallery Background", systemImage: "photo.on.rectangle")
                    .foregroundStyle(AppTheme.textPrimary)
            }
            NavigationLink(destination: GlassSettingsView()) {
                Label("Liquid Glass", systemImage: "circle.hexagongrid.fill")
                    .foregroundStyle(AppTheme.textPrimary)
            }
            NavigationLink(destination: LuaThemePresetsView()) {
                HStack {
                    Label("Lua Theme Presets", systemImage: "scroll.fill")
                        .foregroundStyle(AppTheme.textPrimary)
                    Spacer()
                    if let activeID = LuaThemeEngine.shared.activePresetID,
                       let preset = LuaPreset(rawValue: activeID) {
                        Text(preset.displayName)
                            .font(AppTheme.bodyFont(size: 13))
                            .foregroundStyle(AppTheme.textSecondary)
                    }
                }
            }

            // Navbar mode — same setting Now Playing's own toggle controls
            // (see NowPlayingView's "Navbar Mode" row), sharing one
            // @AppStorage key so either surface always reflects the other's
            // current choice.
            VStack(alignment: .leading, spacing: 8) {
                Label("Navbar Mode", systemImage: "rectangle.bottomthird.inset.filled")
                    .foregroundStyle(AppTheme.textPrimary)
                Picker("Navbar Mode", selection: $navbarDisplayMode) {
                    ForEach(NavbarDisplayMode.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                Text("Mini Player replaces the tab bar with artwork, a seeker, and transport controls whenever a song is loaded — the bar's size never changes, only what's inside it.")
                    .font(.caption)
                    .foregroundStyle(AppTheme.textSecondary)
            }
            .padding(.vertical, 4)
        } header: {
            sectionHeader("Appearance", icon: "paintbrush.fill", tint: .purple)
        }
        .listRowBackground(tintedRowBackground(.purple))
    }
}
