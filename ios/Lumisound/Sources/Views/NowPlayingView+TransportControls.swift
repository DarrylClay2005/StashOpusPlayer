import SwiftUI
import UIKit

extension NowPlayingView {

    // MARK: - Transport Controls

    var transportSection: some View {
        HStack(spacing: 0) {
            // Shuffle — active state shows a filled accent well.
            transportButton(
                systemName: "shuffle",
                font: .system(size: 18, weight: .semibold),
                isActive: player.shuffleEnabled
            ) {
                player.toggleShuffle()
            }

            Spacer()

            // Previous
            transportButton(
                systemName: "backward.fill",
                font: .system(size: 24, weight: .medium),
                isActive: false
            ) {
                skipHaptic.impactOccurred()
                player.skipToPrevious()
            }

            Spacer()

            // Play / Pause — centered, always 72pt circle with a soft gradient
            // and press-scale feedback for a more tactile, modern feel.
            Button {
                playHaptic.impactOccurred()
                player.togglePlayPause()
            } label: {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [AppTheme.dynamicAccent, AppTheme.accentSoft],
                                startPoint: .topLeading, endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 72, height: 72)
                        .overlay(Circle().stroke(.white.opacity(0.18), lineWidth: 1))
                        .shadow(color: AppTheme.dynamicAccent.opacity(0.5), radius: 16, x: 0, y: 8)
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(.white)
                        .contentTransition(.opacity)
                }
            }
            .buttonStyle(PressableButtonStyle())
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: player.isPlaying)

            Spacer()

            // Next
            transportButton(
                systemName: "forward.fill",
                font: .system(size: 24, weight: .medium),
                isActive: false
            ) {
                skipHaptic.impactOccurred()
                player.skipToNext()
            }

            Spacer()

            // Repeat — active (all/one) shows a filled accent well.
            transportButton(
                systemName: repeatIcon,
                font: .system(size: 18, weight: .semibold),
                isActive: player.repeatMode != .off
            ) {
                player.cycleRepeatMode()
            }
        }
        .padding(.vertical, 4)
    }

    var repeatIcon: String {
        switch player.repeatMode {
        case .off:  return "repeat"
        case .all:  return "repeat"
        case .one:  return "repeat.1"
        }
    }

    /// A secondary transport control rendered as an icon inside a subtle
    /// circular "well" — glass when active (accent-tinted), faint surface
    /// otherwise — with press-scale feedback.
    func transportButton(
        systemName: String,
        font: Font,
        isActive: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(font)
                .foregroundStyle(isActive ? .white : AppTheme.textPrimary)
                .frame(width: 46, height: 46)
                .background(
                    Circle().fill(
                        isActive
                            ? AppTheme.dynamicAccent.opacity(0.9)
                            : AppTheme.elevatedSurface.opacity(0.5)
                    )
                )
                .overlay(
                    Circle().stroke(.white.opacity(isActive ? 0.25 : 0.08), lineWidth: 1)
                )
        }
        .buttonStyle(PressableButtonStyle())
        .animation(.easeInOut(duration: 0.2), value: isActive)
    }
}
