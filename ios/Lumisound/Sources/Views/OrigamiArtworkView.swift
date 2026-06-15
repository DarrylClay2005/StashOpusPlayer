import SwiftUI

// MARK: - OrigamiArtworkView
//
// The artwork is presented as a folded paper card: a triangular corner fold
// reveals a solid color sampled from the artwork's palette, faint crease
// lines suggest where the paper has been folded, and the whole card flutters
// gently in 3D like a sheet of paper settling.

struct OrigamiArtworkView: View {
    let song: Song?
    let isPlaying: Bool

    @EnvironmentObject private var library: LibraryManager

    @State private var palette: ArtworkPalette?
    @State private var flutter = false
    @State private var floating = false

    private let artSize: CGFloat = 250
    private let foldSize: CGFloat = 54

    var body: some View {
        VStack(spacing: 14) {
            ZStack(alignment: .topTrailing) {
                artworkContent
                    .frame(width: artSize, height: artSize)
                    .clipShape(FoldedCornerShape(fold: foldSize))
                    .overlay(
                        FoldedCornerShape(fold: foldSize)
                            .stroke(.white.opacity(0.12), lineWidth: 1)
                    )
                    .overlay(creaseLines)
                    .overlay(
                        FilmGrainOverlay()
                            .frame(width: artSize, height: artSize)
                            .blendMode(.overlay)
                            .opacity(0.10)
                            .clipShape(FoldedCornerShape(fold: foldSize))
                            .allowsHitTesting(false)
                    )

                // The folded-back corner — backside of the paper, tinted
                // with a color sampled from the artwork itself.
                FoldTriangleShape()
                    .fill(
                        LinearGradient(
                            colors: [
                                (palette?.secondary ?? AppTheme.dynamicAccent).opacity(0.95),
                                (palette?.primary ?? AppTheme.accentSoft).opacity(0.75),
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: foldSize, height: foldSize)
                    .overlay(
                        FoldTriangleShape()
                            .stroke(.black.opacity(0.18), lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.3), radius: 6, x: -2, y: 2)
                    .allowsHitTesting(false)
            }
            .shadow(color: .black.opacity(0.4), radius: floating ? 26 : 14, x: 0, y: floating ? 16 : 8)
            .rotation3DEffect(.degrees(flutter ? 2.2 : -2.2), axis: (x: 0, y: 1, z: 0), perspective: 0.5)
            .rotation3DEffect(.degrees(flutter ? -0.8 : 0.8), axis: (x: 1, y: 0, z: 0), perspective: 0.5)
            .offset(y: floating ? -7 : 0)

            VStack(spacing: 2) {
                Text(song?.displayName ?? "Nothing Playing")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(AppTheme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                if let artist = song?.artistName, !artist.isEmpty {
                    Text(artist)
                        .font(.system(size: 13))
                        .foregroundStyle(AppTheme.textSecondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: artSize)
        }
        .onAppear { updateAnimations(playing: isPlaying) }
        .onChange(of: isPlaying) { playing in updateAnimations(playing: playing) }
        .task(id: song?.id) { await loadPalette() }
        .animation(.easeInOut(duration: 1.2), value: palette)
    }

    /// Faint diagonal creases — a couple of low-opacity strokes drawn once,
    /// suggesting the paper has been folded into thirds.
    private var creaseLines: some View {
        Canvas { context, size in
            let crease1 = Path { p in
                p.move(to: CGPoint(x: 0, y: size.height * 0.36))
                p.addLine(to: CGPoint(x: size.width, y: size.height * 0.40))
            }
            let crease2 = Path { p in
                p.move(to: CGPoint(x: 0, y: size.height * 0.70))
                p.addLine(to: CGPoint(x: size.width, y: size.height * 0.66))
            }
            context.stroke(crease1, with: .color(.black.opacity(0.10)), lineWidth: 1)
            context.stroke(crease2, with: .color(.white.opacity(0.08)), lineWidth: 1)
        }
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private var artworkContent: some View {
        if let song {
            ArtworkThumbnail(song: song, size: artSize)
                .environmentObject(library)
        } else {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [AppTheme.surface, AppTheme.elevatedSurface],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: artSize, height: artSize)
                .overlay {
                    Image(systemName: "music.note")
                        .font(.system(size: 64, weight: .semibold))
                        .foregroundStyle(AppTheme.dynamicAccent)
                }
        }
    }

    private func loadPalette() async {
        palette = await ArtworkPaletteLoader.palette(for: song, library: library)
    }

    private func updateAnimations(playing: Bool) {
        if playing {
            withAnimation(.easeInOut(duration: 4.2).repeatForever(autoreverses: true)) {
                flutter = true
            }
            withAnimation(.easeInOut(duration: 2.6).repeatForever(autoreverses: true)) {
                floating = true
            }
        } else {
            withAnimation(.easeOut(duration: 0.6)) {
                flutter = false
                floating = false
            }
        }
    }
}

// MARK: - FoldedCornerShape

/// A rounded rectangle with its top-trailing corner cut away on the diagonal,
/// leaving a triangular notch for `FoldTriangleShape` to fill.
struct FoldedCornerShape: Shape {
    let fold: CGFloat
    var cornerRadius: CGFloat = 6

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + cornerRadius, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - fold, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + fold))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - cornerRadius))
        path.addArc(
            center: CGPoint(x: rect.maxX - cornerRadius, y: rect.maxY - cornerRadius),
            radius: cornerRadius, startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false
        )
        path.addLine(to: CGPoint(x: rect.minX + cornerRadius, y: rect.maxY))
        path.addArc(
            center: CGPoint(x: rect.minX + cornerRadius, y: rect.maxY - cornerRadius),
            radius: cornerRadius, startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false
        )
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + cornerRadius))
        path.addArc(
            center: CGPoint(x: rect.minX + cornerRadius, y: rect.minY + cornerRadius),
            radius: cornerRadius, startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false
        )
        path.closeSubpath()
        return path
    }
}

// MARK: - FoldTriangleShape

/// The small triangle that fills the notch cut by `FoldedCornerShape`,
/// representing the folded-back corner of the paper.
struct FoldTriangleShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}
