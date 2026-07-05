import SwiftUI
import UIKit

extension NowPlayingView {

    // MARK: - Sleep Timer Pill

    @ViewBuilder
    var sleepTimerPill: some View {
        if sleepTimer.isActive {
            Button {
                showSleepTimerSheet = true
            } label: {
                HStack(spacing: 6) {
                    Text("💤")
                        .font(.caption)
                    Text(sleepTimer.formattedRemaining)
                        .font(.system(.caption, design: .monospaced).weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(AppTheme.textPrimary)
                        .contentTransition(.numericText())
                        .animation(.linear(duration: 0.5), value: sleepTimer.remainingSeconds)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .adaptiveGlass(tint: AppTheme.dynamicAccent, in: Capsule(), fallback: .regularMaterial)
                .overlay(
                    Capsule()
                        .strokeBorder(AppTheme.dynamicAccent.opacity(0.4), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .transition(.scale.combined(with: .opacity))
            .animation(.spring(response: 0.35, dampingFraction: 0.75), value: sleepTimer.isActive)
        }
    }
}
