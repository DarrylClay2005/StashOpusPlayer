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
        } header: {
            sectionHeader("Appearance")
        }
        .listRowBackground(AppTheme.surface)
    }
}
