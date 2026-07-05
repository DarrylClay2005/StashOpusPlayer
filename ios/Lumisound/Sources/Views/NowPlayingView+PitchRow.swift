import SwiftUI
import UIKit

extension NowPlayingView {

    // MARK: - Pitch Row

    var pitchRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Pitch")
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.textPrimary)
                Spacer()
                if editingPitch {
                    TextField("", text: $pitchInput)
                        .keyboardType(.numbersAndPunctuation)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 80)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { applyPitchInput() }
                        .onAppear { pitchInput = String(format: "%.1f", player.audioSettings.pitchSemitones) }
                        .toolbar {
                            ToolbarItemGroup(placement: .keyboard) {
                                Spacer()
                                Button("Done") { applyPitchInput() }
                            }
                        }
                } else {
                    HStack(spacing: 4) {
                        Text(String(format: "%.0f st", player.audioSettings.pitchSemitones))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(AppTheme.textSecondary)
                            .onTapGesture { editingPitch = true }
                        Image(systemName: "pencil")
                            .font(.caption2)
                            .foregroundStyle(AppTheme.textSecondary)
                            .onTapGesture { editingPitch = true }
                    }
                }
            }
            Slider(value: audioBinding(\.pitchSemitones), in: -12...12)
                .tint(AppTheme.dynamicAccent)
        }
    }
}
