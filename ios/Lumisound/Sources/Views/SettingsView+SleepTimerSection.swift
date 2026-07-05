import MediaPlayer
import SwiftUI

extension SettingsView {

    // MARK: — Sleep Timer Section

    var sleepTimerSection: some View {
        Section {
            if sleepTimer.isActive {
                HStack {
                    Label("Active — \(sleepTimer.formattedRemaining)", systemImage: "moon.zzz")
                        .foregroundStyle(AppTheme.textPrimary)
                        .font(.system(.subheadline).monospacedDigit())
                    Spacer()
                    Button("Cancel") {
                        sleepTimer.cancel()
                        ToastCenter.shared.show("Sleep timer cancelled", category: .info, icon: "moon.zzz")
                    }
                    .foregroundStyle(AppTheme.warning)
                }
            } else {
                Picker("Duration", selection: $sleepTimer.selectedDuration) {
                    ForEach(SleepTimerService.presets, id: \.seconds) { preset in
                        Text(preset.label).tag(preset.seconds)
                    }
                }
                .pickerStyle(.menu)
                .tint(AppTheme.dynamicAccent)
                .foregroundStyle(AppTheme.textPrimary)

                Button {
                    sleepTimer.start()
                    ToastCenter.shared.show("Sleep timer started", category: .success, icon: "moon.zzz.fill")
                } label: {
                    Label("Start Sleep Timer", systemImage: "moon.zzz")
                        .foregroundStyle(AppTheme.dynamicAccent)
                }
            }
        } header: {
            sectionHeader("Sleep Timer")
        }
        .listRowBackground(AppTheme.surface)
    }
}
