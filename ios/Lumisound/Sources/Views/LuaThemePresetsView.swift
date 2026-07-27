import SwiftUI

// MARK: - LuaThemePresetsView
//
// Runtime preset switcher for the Lua-scripted theming/logic layer (see
// `Theme/LuaThemeEngine.swift`). Follows the same list-of-tappable-swatches
// + toast-on-select pattern `AppearanceView`'s "Background Theme" and "Quick
// Picks" sections already use, so applying a Lua preset feels like just
// another built-in appearance option rather than a bolted-on system.

struct LuaThemePresetsView: View {
    @ObservedObject private var engine = LuaThemeEngine.shared
    @State private var refreshToken = UUID()

    var body: some View {
        List {
            Section {
                Text("Each preset is a small Lua script that sets the app's colors, fonts, panel/glass style, a few behavior flags, and the Library tab's default sort — all in one tap. Applying one overwrites the individual choices in Appearance, Liquid Glass, and the Library sort chips.")
                    .font(AppTheme.bodyFont(size: 13))
                    .foregroundStyle(AppTheme.textSecondary)
                    .listRowBackground(Color.clear)
            }

            if let error = engine.lastError {
                Section {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(AppTheme.bodyFont(size: 13))
                        .foregroundStyle(AppTheme.error)
                }
                .listRowBackground(AppTheme.surface)
            }

            Section {
                ForEach(LuaPreset.allCases) { preset in
                    presetRow(preset)
                }
            } header: {
                sectionHeader("Presets")
            }
            .listRowBackground(AppTheme.surface)

            if engine.activePresetID != nil {
                Section {
                    Button(role: .destructive) {
                        engine.clearPreset()
                        refreshToken = UUID()
                        ToastCenter.shared.show("Lua preset cleared", category: .info, icon: "arrow.counterclockwise")
                    } label: {
                        HStack {
                            Image(systemName: "xmark.circle")
                            Text("Clear Active Preset")
                        }
                    }
                    .foregroundStyle(AppTheme.dynamicAccent)
                }
                .listRowBackground(AppTheme.surface)
                .listRowSeparator(.hidden)
                Section {
                    Text("Clearing only removes the preset marker and the custom background/layout scale it set — individual colors, fonts, and styles stay as the preset left them. Use Appearance → Reset to Default to restore everything.")
                        .font(AppTheme.bodyFont(size: 12))
                        .foregroundStyle(AppTheme.textSecondary)
                        .listRowBackground(Color.clear)
                }
            }
        }
        .id(refreshToken)
        .scrollContentBackground(.hidden)
        .background(Color.clear.ignoresSafeArea())
        .navigationTitle("Lua Theme Presets")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func presetRow(_ preset: LuaPreset) -> some View {
        let isActive = engine.activePresetID == preset.rawValue
        let swatches = preset.previewColors

        return Button {
            let ok = engine.apply(preset)
            refreshToken = UUID()
            if ok {
                ToastCenter.shared.show("Applied “\(preset.displayName)”", category: .success, icon: preset.iconName)
            } else {
                ToastCenter.shared.show(engine.lastError ?? "Couldn't apply that preset", category: .error, icon: "exclamationmark.triangle.fill")
            }
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(swatches.background)
                        .frame(width: 40, height: 40)
                    Circle()
                        .fill(swatches.accent)
                        .frame(width: 18, height: 18)
                        .offset(x: 10, y: 10)
                }
                .overlay(
                    Circle()
                        .strokeBorder(.white.opacity(0.12), lineWidth: 1)
                        .frame(width: 40, height: 40)
                )

                VStack(alignment: .leading, spacing: 2) {
                    Text(preset.displayName)
                        .font(AppTheme.headlineFont(size: 15))
                        .foregroundStyle(AppTheme.textPrimary)
                    Text(preset.subtitle)
                        .font(AppTheme.bodyFont(size: 12))
                        .foregroundStyle(AppTheme.textSecondary)
                }

                Spacer()

                if isActive {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(AppTheme.dynamicAccent)
                } else {
                    Image(systemName: preset.iconName)
                        .foregroundStyle(AppTheme.textSecondary)
                }
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(AppTheme.bodyFont())
            .foregroundStyle(AppTheme.textSecondary)
    }
}
