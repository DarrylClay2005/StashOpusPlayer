import MediaPlayer
import SwiftUI

extension SettingsView {

    // MARK: — App Updates Section

    var updatesSection: some View {
        Section {
            // Version info row
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Current Version")
                        .foregroundStyle(AppTheme.textPrimary)
                    Text(updater.currentVersion)
                        .font(AppTheme.monoFont(size: 13))
                        .foregroundStyle(AppTheme.textSecondary)
                }
                Spacer()
                if updater.updateAvailable, let latest = updater.latestVersion {
                    Text("→ \(latest)")
                        .font(AppTheme.monoFont(size: 13))
                        .foregroundStyle(AppTheme.success)
                }
            }

            // Download update button — only when available
            if updater.updateAvailable {
                Button {
                    updater.openReleasePage()
                } label: {
                    Label(
                        updater.directDownloadURL != nil
                            ? "Download v\(updater.latestVersion ?? "") IPA"
                            : "Download Update",
                        systemImage: "arrow.down.circle"
                    )
                    .foregroundStyle(AppTheme.dynamicAccent)
                }
            }

            // Check for updates button
            Button {
                Task { await updater.checkForUpdates() }
            } label: {
                HStack {
                    Label("Check for Updates", systemImage: "arrow.clockwise")
                        .foregroundStyle(AppTheme.dynamicAccent)
                    Spacer()
                    if updater.isChecking {
                        ProgressView()
                            .tint(AppTheme.dynamicAccent)
                    }
                }
            }
            .disabled(updater.isChecking)

        } header: {
            sectionHeader("App Updates", icon: "arrow.triangle.2.circlepath", tint: .green)
        }
        .listRowBackground(AppTheme.surface)
    }
}
