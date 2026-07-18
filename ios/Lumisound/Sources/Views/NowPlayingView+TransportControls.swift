import SwiftUI
import UIKit

extension NowPlayingView {

    // MARK: - Transport Controls
    //
    // 2026-07 redesign: control identity/order/visibility/size is now driven
    // by `screenStyle` (resolved from a selected Custom Style's
    // `transportControlOrder`/`hiddenTransportControls`/`transportControlScale`)
    // instead of a fixed shuffle/prev/play/next/repeat layout. Selecting a
    // built-in artwork style (or no custom style) resolves to
    // `NowPlayingScreenStyle.standard`, whose `transportOrder` is the same
    // `TransportControl.allCases` order as before — so the default look is
    // pixel-identical to the pre-redesign layout.

    /// Controls in the user's chosen order, minus any explicitly hidden.
    /// `playPause` can never be hidden (`CustomNowPlayingStyle.sanitized()`
    /// strips it from `hiddenTransportControls` before this ever sees it).
    var visibleTransportControls: [CustomNowPlayingStyle.TransportControl] {
        screenStyle.transportOrder.filter { !screenStyle.hiddenTransportControls.contains($0) }
    }

    /// Controls that render to the left of Play/Pause — Play/Pause always
    /// stays visually centered regardless of where it falls in the saved
    /// order; only the *relative* order of the other controls (and which
    /// side of Play/Pause they land on) is actually driven by that order.
    var transportLeftControls: [CustomNowPlayingStyle.TransportControl] {
        guard let idx = visibleTransportControls.firstIndex(of: .playPause) else { return visibleTransportControls }
        return Array(visibleTransportControls[..<idx])
    }

    var transportRightControls: [CustomNowPlayingStyle.TransportControl] {
        guard let idx = visibleTransportControls.firstIndex(of: .playPause) else { return [] }
        return Array(visibleTransportControls[(idx + 1)...])
    }

    var transportSection: some View {
        HStack(spacing: 0) {
            ForEach(transportLeftControls) { control in
                transportControlView(for: control)
                Spacer()
            }
            playPauseButton
            ForEach(transportRightControls) { control in
                Spacer()
                transportControlView(for: control)
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

    /// Play / Pause — centered, a soft gradient circle (accent-driven, so a
    /// custom style's accent color/extracted palette carries through here
    /// too) with press-scale feedback for a tactile, modern feel.
    var playPauseButton: some View {
        let scale = screenStyle.transportScale
        return Button {
            playHaptic.impactOccurred()
            withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
                player.togglePlayPause()
            }
        } label: {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [screenStyle.accentColor, AppTheme.accentSoft],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 72 * scale, height: 72 * scale)
                    .overlay(Circle().stroke(.white.opacity(0.18), lineWidth: 1))
                    .shadow(color: screenStyle.accentColor.opacity(0.5), radius: 16, x: 0, y: 8)
                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 28 * scale, weight: .bold))
                    .foregroundStyle(.white)
                    .symbolReplaceTransition()
            }
        }
        .buttonStyle(PressableButtonStyle())
    }

    /// Resolves one `TransportControl` case to its concrete button.
    @ViewBuilder
    func transportControlView(for control: CustomNowPlayingStyle.TransportControl) -> some View {
        let scale = screenStyle.transportScale
        switch control {
        case .shuffle:
            transportButton(
                systemName: "shuffle",
                font: .system(size: 18 * scale, weight: .semibold),
                isActive: player.shuffleEnabled
            ) {
                selectHaptic.selectionChanged()
                player.toggleShuffle()
            }
        case .previous:
            transportButton(
                systemName: "backward.fill",
                font: .system(size: 24 * scale, weight: .medium),
                isActive: false
            ) {
                skipHaptic.impactOccurred()
                player.skipToPrevious()
            }
        case .playPause:
            playPauseButton
        case .next:
            transportButton(
                systemName: "forward.fill",
                font: .system(size: 24 * scale, weight: .medium),
                isActive: false
            ) {
                skipHaptic.impactOccurred()
                player.skipToNext()
            }
        case .repeatControl:
            transportButton(
                systemName: repeatIcon,
                font: .system(size: 18 * scale, weight: .semibold),
                isActive: player.repeatMode != .off
            ) {
                selectHaptic.selectionChanged()
                player.cycleRepeatMode()
            }
        }
    }

    /// A secondary transport control rendered as an icon inside a subtle
    /// circular "well" — glass when active (accent-tinted), faint surface
    /// otherwise — with press-scale feedback. Size already includes the
    /// screen style's scale factor via the caller-supplied `font`; the
    /// well itself is scaled here too so the tap target grows/shrinks with it.
    func transportButton(
        systemName: String,
        font: Font,
        isActive: Bool,
        action: @escaping () -> Void
    ) -> some View {
        let scale = screenStyle.transportScale
        return Button(action: action) {
            Image(systemName: systemName)
                .font(font)
                .foregroundStyle(isActive ? .white : (screenStyle.controlsColor ?? AppTheme.textPrimary))
                .frame(width: 46 * scale, height: 46 * scale)
                .background(
                    Circle().fill(
                        isActive
                            ? screenStyle.accentColor.opacity(0.9)
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
