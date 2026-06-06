import SwiftUI

// MARK: - GlassmorphismArtworkView
//
// Album art fills the background of a rounded card. A frosted glass
// (.ultraThinMaterial) panel is overlaid on the lower portion showing
// song title and artist, with a thin accent border around the card.

struct GlassmorphismArtworkView: View {
    let song: Song?
    let isPlaying: Bool

    @EnvironmentObject private var library: LibraryManager
    @State private var floating = false
    @State private var borderGlow = false
    @State private var shimmerOffset: CGFloat = -300

    private let cardSize: CGFloat = 300

    var body: some View {
        ZStack(alignment: .bottom) {
            // Full-bleed album art as background
            artBackground

            // Frosted glass info strip at the bottom
            glassInfoStrip
        }
        .frame(width: cardSize, height: cardSize)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(
                    AppTheme.dynamicAccent.opacity(borderGlow ? 0.75 : 0.30),
                    lineWidth: borderGlow ? 2.0 : 1.5
                )
                .animation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true), value: borderGlow)
        )
        .shadow(
            color: AppTheme.dynamicAccent.opacity(borderGlow ? 0.45 : 0.2),
            radius: borderGlow ? 30 : 18,
            x: 0, y: 10
        )
        .animation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true), value: borderGlow)
        .offset(y: floating ? -7 : 0)
        .animation(.easeInOut(duration: 3.2).repeatForever(autoreverses: true), value: floating)
        .onChange(of: isPlaying) { playing in
            updateAnimations(playing: playing)
        }
        .onAppear {
            updateAnimations(playing: isPlaying)
        }
    }

    @ViewBuilder
    private var artBackground: some View {
        if let song {
            ArtworkThumbnail(song: song, size: cardSize)
                .environmentObject(library)
                .overlay(shimmerOverlay)
        } else {
            LinearGradient(
                colors: [AppTheme.surface, AppTheme.elevatedSurface, AppTheme.accent.opacity(0.4)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .frame(width: cardSize, height: cardSize)
            .overlay {
                Image(systemName: "music.note")
                    .font(.system(size: 80, weight: .semibold))
                    .foregroundStyle(AppTheme.accent.opacity(0.6))
            }
            .overlay(shimmerOverlay)
        }
    }

    @ViewBuilder
    private var shimmerOverlay: some View {
        if isPlaying {
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .white.opacity(0.08), location: 0.45),
                    .init(color: .white.opacity(0.15), location: 0.5),
                    .init(color: .white.opacity(0.08), location: 0.55),
                    .init(color: .clear, location: 1),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .frame(width: cardSize * 2)
            .offset(x: shimmerOffset)
            .allowsHitTesting(false)
        }
    }

    private var glassInfoStrip: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(song?.displayName ?? "Nothing Playing")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
            Text(song?.artistName ?? "—")
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(.white.opacity(0.75))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(.ultraThinMaterial)
        // Clip only the bottom corners to match the card
        .clipShape(
            RoundedCornerShape(radius: 20, corners: [.bottomLeft, .bottomRight])
        )
    }

    private func updateAnimations(playing: Bool) {
        floating = playing
        borderGlow = playing
        if playing {
            withAnimation(.linear(duration: 3.0).repeatForever(autoreverses: false)) {
                shimmerOffset = 300
            }
        } else {
            shimmerOffset = -300
        }
    }
}

// MARK: - RoundedCornerShape

/// A shape that rounds only the specified corners — used to apply the glass strip
/// only to the bottom corners so the top edge meets the artwork cleanly.
private struct RoundedCornerShape: Shape {
    var radius: CGFloat
    var corners: UIRectCorner

    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(
            roundedRect: rect,
            byRoundingCorners: corners,
            cornerRadii: CGSize(width: radius, height: radius)
        )
        return Path(path.cgPath)
    }
}
