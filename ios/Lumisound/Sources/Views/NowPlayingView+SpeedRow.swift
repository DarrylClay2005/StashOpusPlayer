import SwiftUI
import UIKit

extension NowPlayingView {

    // MARK: - Speed Row

    var speedRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Speed")
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.textPrimary)
                Spacer()
                if editingSpeed {
                    TextField("", text: $speedInput)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 80)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { applySpeedInput() }
                        .onAppear { speedInput = String(format: "%.2f", player.audioSettings.speed) }
                        .toolbar {
                            ToolbarItemGroup(placement: .keyboard) {
                                Spacer()
                                Button("Done") { applySpeedInput() }
                            }
                        }
                } else {
                    HStack(spacing: 4) {
                        Text(String(format: "%.2fx", player.audioSettings.speed))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(AppTheme.textSecondary)
                            .onTapGesture { editingSpeed = true }
                        Image(systemName: "pencil")
                            .font(.caption2)
                            .foregroundStyle(AppTheme.textSecondary)
                            .onTapGesture { editingSpeed = true }
                    }
                }
            }
            Slider(value: audioBinding(\.speed), in: 0.5...2.0)
                .tint(AppTheme.dynamicAccent)
        }
    }
}
