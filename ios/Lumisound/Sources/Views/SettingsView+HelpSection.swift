import MediaPlayer
import SwiftUI

extension SettingsView {

    // MARK: — Help Section

    var helpSection: some View {
        Section {
            NavigationLink(destination: SettingsHelpView()) {
                Label("Help & Feature Guide", systemImage: "questionmark.circle")
                    .foregroundStyle(AppTheme.textPrimary)
            }
            NavigationLink(destination: BugReportView()) {
                Label("Report a Bug", systemImage: "ladybug")
                    .foregroundStyle(AppTheme.textPrimary)
            }
        } header: {
            sectionHeader("Help")
        }
        .listRowBackground(AppTheme.surface)
    }
}
