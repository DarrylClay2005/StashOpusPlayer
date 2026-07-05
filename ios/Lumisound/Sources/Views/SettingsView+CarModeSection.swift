import SwiftUI

extension SettingsView {

    // MARK: — Car Mode Section

    var carModeSection: some View {
        Section {
            // Car Mode toggle
            Toggle(isOn: $carModeEnabled) {
                Label("Car Mode", systemImage: "car.fill")
                    .foregroundStyle(AppTheme.textPrimary)
            }
            .tint(AppTheme.dynamicAccent)

            if carModeEnabled {
                Text("Shows a large-button driving layout, accessible from the floating car icon or automatically when connected to a car stereo.")
                    .font(.caption)
                    .foregroundStyle(AppTheme.textSecondary)
                    .padding(.leading, 16)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            } else {
                Text("Hides the Car Mode button and disables automatic switching when connected to a car stereo.")
                    .font(.caption)
                    .foregroundStyle(AppTheme.textSecondary)
                    .padding(.leading, 16)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        } header: {
            sectionHeader("Car Mode")
        }
        .listRowBackground(AppTheme.surface)
        .animation(.easeInOut(duration: 0.22), value: carModeEnabled)
    }
}
