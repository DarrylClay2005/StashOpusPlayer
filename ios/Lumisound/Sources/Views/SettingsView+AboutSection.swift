import MediaPlayer
import SwiftUI

extension SettingsView {

    // MARK: — About Section

    var aboutSection: some View {
        Section {
            LabeledContent("App") {
                Text("Lumisound")
                    .foregroundStyle(AppTheme.textSecondary)
            }
            .foregroundStyle(AppTheme.textPrimary)

            HStack {
                Label("Version", systemImage: updater.updateStatusIcon)
                    .foregroundStyle(AppTheme.textPrimary)
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(updater.currentVersion)
                        .font(AppTheme.monoFont(size: 13))
                        .foregroundStyle(AppTheme.textSecondary)
                    Text(updater.updateStatusText)
                        .font(.caption)
                        .foregroundStyle(updater.updateStatusColor)
                }
            }

            Button {
                Task { await updater.checkForUpdates() }
            } label: {
                HStack {
                    Label("Check Now", systemImage: "arrow.clockwise")
                        .foregroundStyle(AppTheme.dynamicAccent)
                    Spacer()
                    if updater.isChecking {
                        ProgressView()
                            .tint(AppTheme.dynamicAccent)
                    }
                }
            }
            .disabled(updater.isChecking)

            if !WidgetDataService.shared.isAppGroupAvailable {
                VStack(alignment: .leading, spacing: 4) {
                    Label("Widgets Unavailable", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                    Text("This build can't share data with its Lock Screen and Home Screen widgets, so they'll stay on their placeholder. This usually means the App Group entitlement (group.com.lumisound.ios) wasn't preserved when this app was signed — re-signing tools need to include that App Group in the provisioning profile for widgets to work.")
                        .font(.caption)
                        .foregroundStyle(AppTheme.textSecondary)
                }
                .padding(.vertical, 2)
            }

            // Open Source Libraries
            VStack(alignment: .leading, spacing: 6) {
                Text("Open Source Libraries")
                    .font(AppTheme.bodyFont())
                    .foregroundStyle(AppTheme.textPrimary)
                ForEach(["AVFoundation", "SwiftUI", "MediaPlayer"], id: \.self) { lib in
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(AppTheme.success)
                        Text(lib)
                            .font(AppTheme.bodyFont(size: 13))
                            .foregroundStyle(AppTheme.textSecondary)
                    }
                }
            }
            .padding(.vertical, 4)

            // Credit line
            HStack {
                Spacer()
                Text("Built with AVFoundation & SwiftUI")
                    .font(AppTheme.bodyFont(size: 12))
                    .foregroundStyle(AppTheme.textSecondary)
                    .italic()
                Spacer()
            }

        } header: {
            sectionHeader("About", icon: "info.circle.fill", tint: .gray)
        }
        .listRowBackground(AppTheme.surface)
    }
}
