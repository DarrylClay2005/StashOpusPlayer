import SwiftUI

extension SettingsView {

    // MARK: — App Lock Section

    @ViewBuilder
    var appLockSection: some View {
        if appLock.biometryAvailable() {
            Section {
                Toggle(isOn: $appLock.isEnabled) {
                    Label("Require \(appLock.biometryTypeName)", systemImage: "lock.shield")
                        .foregroundStyle(AppTheme.textPrimary)
                }
                .tint(AppTheme.dynamicAccent)
            } header: {
                sectionHeader("App Lock")
            } footer: {
                Text("Lock Lumisound behind \(appLock.biometryTypeName) whenever it's reopened from the background. Your account syncs playlists and listening history, so this adds a second layer beyond your device's own lock screen.")
                    .font(.caption)
                    .foregroundStyle(AppTheme.textSecondary)
            }
            .listRowBackground(AppTheme.surface)
        }
    }
}
