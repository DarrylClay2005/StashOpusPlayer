import SwiftUI

extension NowPlayingView {

    // MARK: - Workout Mode

    /// Toggle for `WorkoutModeService` — nudges playback speed to track the
    /// user's live step cadence (see that service's own doc comment for how).
    var workoutModeSection: some View {
        WorkoutModeToggleCard()
    }
}

private struct WorkoutModeToggleCard: View {
    @ObservedObject private var workout = WorkoutModeService.shared

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "figure.run")
                .font(.system(size: 16))
                .foregroundStyle(workout.isActive ? AppTheme.dynamicAccent : AppTheme.textSecondary)

            VStack(alignment: .leading, spacing: 2) {
                Text("Workout Mode")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.textPrimary)
                Text(statusText)
                    .font(.caption)
                    .foregroundStyle(AppTheme.textSecondary)
            }

            Spacer(minLength: 8)

            Toggle("", isOn: Binding(
                get: { workout.isActive },
                set: { newValue in
                    if newValue {
                        workout.start()
                    } else {
                        workout.stop()
                    }
                }
            ))
            .labelsHidden()
            .tint(AppTheme.dynamicAccent)
            .disabled(!workout.isAvailable)
        }
        .panelStyle()
    }

    private var statusText: String {
        guard workout.isAvailable else {
            return "Step counting isn't available on this device."
        }
        if let error = workout.lastError {
            return error
        }
        if workout.isActive, let spm = workout.currentCadenceSPM {
            return "\(Int(spm.rounded())) steps/min — playback speed is matching your pace."
        }
        if workout.isActive {
            return "Reading your pace…"
        }
        return "Nudges playback speed to match your walking/running cadence."
    }
}
