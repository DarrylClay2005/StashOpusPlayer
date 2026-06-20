import SwiftUI

// MARK: - GlassmorphismArtworkView
//
// True glassmorphism: a large blurred copy of the artwork fills the backdrop,
// a frosted translucent glass card floats on top with a diagonal light streak,
// and the crisp cover is inset inside the glass. Layered depth + real blur,
// not just a frosted strip.

struct GlassmorphismArtworkView: View {
    let song: Song?
    let isPlaying: Bool

    @EnvironmentObject private var library: LibraryManager
    @State private var palette: ArtworkPalette?
    @State private var floating = false
    @State private var streak: CGFloat = -1.2

    private let cardSize: CGFloat = 300
    private let cardShape = RoundedRectangle(cornerRadius: 28, style: .continuous)

    var body: some View {
        ZStack {
            // Blurred enlarged artwork backdrop.
            artwork(size: 340)
                .frame(width: cardSize, height: cardSize)
                .clipped()
                .blur(radius: 36)
                .overlay((palette?.primary ?? AppTheme.dynamicAccent).opacity(0.12))
                .clipShape(cardShape)

            // Frosted glass card with a sweeping light streak.
            cardShape
                .fill(.ultraThinMaterial)
                .overlay(
                    GeometryReader { geo in
                        LinearGradient(colors: [.clear, .white.opacity(0.35), .clear],
                                       startPoint: .topLeading, endPoint: .bottomTrailing)
                            .frame(width: geo.size.width * 0.5)
                            .rotationEffect(.degrees(24))
                            .offset(x: streak * geo.size.width)
                            .blendMode(.plusLighter)
                    }
                    .clipShape(cardShape)
                )
                .overlay(cardShape.stroke(.white.opacity(0.25), lineWidth: 1))
                .frame(width: cardSize, height: cardSize)

            // Crisp inset cover + label.
            VStack(spacing: 14) {
                artwork(size: 196)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(.white.opacity(0.25), lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.35), radius: 16, x: 0, y: 10)

                VStack(spacing: 3) {
                    Text(song?.displayName ?? "Nothing Playing")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text(song?.artistName ?? "—")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.75))
                        .lineLimit(1)
                }
                .padding(.horizontal, 16)
            }
        }
        .frame(width: cardSize, height: cardSize)
        .shadow(color: (palette?.primary ?? AppTheme.dynamicAccent).opacity(0.4), radius: 26, x: 0, y: 12)
        .offset(y: floating ? -7 : 0)
        .onAppear { animate(playing: isPlaying) }
        .onChange(of: isPlaying) { animate(playing: $0) }
        .task(id: song?.id) { palette = await ArtworkPaletteLoader.palette(for: song, library: library) }
        .animation(.easeInOut(duration: 1.0), value: palette)
    }

    private func animate(playing: Bool) {
        if playing {
            withAnimation(.easeInOut(duration: 3.2).repeatForever(autoreverses: true)) { floating = true }
            withAnimation(.easeInOut(duration: 3.0).repeatForever(autoreverses: false)) { streak = 1.2 }
        } else {
            withAnimation(.easeOut(duration: 0.6)) { floating = false; streak = 0 }
        }
    }

    @ViewBuilder
    private func artwork(size: CGFloat) -> some View {
        if let song {
            ArtworkThumbnail(song: song, size: size)
                .environmentObject(library)
        } else {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(LinearGradient(colors: [AppTheme.surface, AppTheme.elevatedSurface],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: size, height: size)
                .overlay {
                    Image(systemName: "music.note")
                        .font(.system(size: size * 0.27, weight: .semibold))
                        .foregroundStyle(AppTheme.dynamicAccent)
                }
        }
    }
}
