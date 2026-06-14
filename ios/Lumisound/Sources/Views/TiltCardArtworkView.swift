import SwiftUI

// MARK: - TiltCardArtworkView
//
// A 3D "floating card" perspective effect: the artwork gently rocks back
// and forth in 3D space with a soft drop shadow that shifts opposite the
// tilt, like a card hovering above the background.

struct TiltCardArtworkView: View {
    let song: Song?
    let isPlaying: Bool
    @EnvironmentObject private var library: LibraryManager

    @State private var tiltX: Double = 0
    @State private var tiltY: Double = 0

    var body: some View {
        Group {
            if let song {
                ArtworkThumbnail(song: song, size: 290)
                    .environmentObject(library)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            } else {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [AppTheme.surface, AppTheme.elevatedSurface],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 290, height: 290)
                    .overlay {
                        Image(systemName: "music.note")
                            .font(.system(size: 78, weight: .semibold))
                            .foregroundStyle(AppTheme.dynamicAccent)
                    }
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(.white.opacity(0.15), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.45), radius: 22, x: -tiltY * 1.4, y: tiltX * 1.4 + 14)
        .rotation3DEffect(.degrees(tiltX), axis: (x: 1, y: 0, z: 0), perspective: 0.4)
        .rotation3DEffect(.degrees(tiltY), axis: (x: 0, y: 1, z: 0), perspective: 0.4)
        .frame(width: 300, height: 300)
        .onAppear { updateAnimations(playing: isPlaying) }
        .onChange(of: isPlaying) { playing in updateAnimations(playing: playing) }
    }

    private func updateAnimations(playing: Bool) {
        if playing {
            withAnimation(.easeInOut(duration: 5).repeatForever(autoreverses: true)) {
                tiltX = 6
            }
            withAnimation(.easeInOut(duration: 6.5).repeatForever(autoreverses: true)) {
                tiltY = -8
            }
        } else {
            withAnimation(.easeOut(duration: 0.8)) {
                tiltX = 0
                tiltY = 0
            }
        }
    }
}
