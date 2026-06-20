import SwiftUI

// MARK: - PrismBeamsArtworkView
//
// The cover seen through a glass prism: a bold rainbow spectrum band refracts
// diagonally across the artwork (a real dispersion sweep), volumetric
// spectrum beams fan out and rotate behind it, and the cover edge carries a
// chromatic fringe — light splitting into color through glass.

struct PrismBeamsArtworkView: View {
    let song: Song?
    let isPlaying: Bool

    @EnvironmentObject private var library: LibraryManager

    @State private var rotation: Double = 0
    @State private var glow = false
    @State private var palette: ArtworkPalette?

    private let artSize: CGFloat = 220
    private let beamLength: CGFloat = 96
    private let beamCount = 10
    private let artShape = RoundedRectangle(cornerRadius: 20, style: .continuous)

    /// A full visible spectrum, used for both the dispersion band and beams.
    private let spectrum: [Color] = [
        Color(red: 1.0, green: 0.2, blue: 0.25),
        Color(red: 1.0, green: 0.6, blue: 0.1),
        Color(red: 1.0, green: 0.95, blue: 0.2),
        Color(red: 0.3, green: 0.9, blue: 0.4),
        Color(red: 0.2, green: 0.7, blue: 1.0),
        Color(red: 0.55, green: 0.3, blue: 1.0),
    ]

    private var canvasSize: CGFloat { artSize + beamLength * 2 }

    var body: some View {
        ZStack {
            // Volumetric spectrum beams, rotating behind the cover.
            beams
                .frame(width: canvasSize, height: canvasSize)
                .rotationEffect(.degrees(rotation))
                .blendMode(.plusLighter)

            centralArt
        }
        .frame(width: canvasSize, height: canvasSize)
        .onAppear { if isPlaying { startAnimations() } }
        .onChange(of: isPlaying) { playing in
            if playing { startAnimations() } else { stopAnimations() }
        }
        .task(id: song?.id) { await loadPalette() }
        .animation(.easeInOut(duration: 1.2), value: palette)
    }

    private var beams: some View {
        ZStack {
            ForEach(0..<beamCount, id: \.self) { i in
                Capsule()
                    .fill(
                        LinearGradient(colors: [spectrum[i % spectrum.count], .clear],
                                       startPoint: .leading, endPoint: .trailing)
                    )
                    .frame(width: beamLength, height: 6)
                    .offset(x: artSize / 2 + beamLength / 2 - 8)
                    .rotationEffect(.degrees(Double(i) * (360.0 / Double(beamCount))))
                    .blur(radius: 3)
                    .opacity(isPlaying ? 0.7 : 0.25)
            }
        }
    }

    private var centralArt: some View {
        artwork
            .frame(width: artSize, height: artSize)
            .clipShape(artShape)
            // Refracted rainbow band sweeping diagonally across the cover.
            .overlay(dispersionBand.clipShape(artShape).allowsHitTesting(false))
            // Chromatic-fringe border — offset tinted strokes, like a prism
            // splitting light at the card's edge.
            .overlay(artShape.stroke((palette?.primary ?? .cyan).opacity(0.5), lineWidth: 1.5).offset(x: -1.5))
            .overlay(artShape.stroke((palette?.secondary ?? .pink).opacity(0.5), lineWidth: 1.5).offset(x: 1.5))
            .overlay(artShape.stroke(.white.opacity(0.18), lineWidth: 1))
            .shadow(color: (palette?.primary ?? AppTheme.dynamicAccent).opacity(glow ? 0.5 : 0.2),
                    radius: glow ? 26 : 12, x: 0, y: 0)
            .animation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true), value: glow)
    }

    private var dispersionBand: some View {
        LinearGradient(colors: [.clear] + spectrum.map { $0.opacity(0.45) } + [.clear],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
            .frame(width: artSize * 1.5, height: artSize * 0.5)
            .rotationEffect(.degrees(38))
            .blur(radius: 6)
            .blendMode(.plusLighter)
            .opacity(isPlaying ? 0.9 : 0.4)
    }

    @ViewBuilder
    private var artwork: some View {
        if let song {
            ArtworkThumbnail(song: song, size: artSize)
                .environmentObject(library)
        } else {
            artShape
                .fill(LinearGradient(colors: [AppTheme.surface, AppTheme.elevatedSurface],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: artSize, height: artSize)
                .overlay {
                    Image(systemName: "music.note")
                        .font(.system(size: 60, weight: .semibold))
                        .foregroundStyle(AppTheme.dynamicAccent)
                }
        }
    }

    private func loadPalette() async {
        palette = await ArtworkPaletteLoader.palette(for: song, library: library)
    }

    private func startAnimations() {
        glow = true
        withAnimation(.linear(duration: 60).repeatForever(autoreverses: false)) { rotation = 360 }
    }

    private func stopAnimations() {
        glow = false
        withAnimation(.easeOut(duration: 0.8)) { rotation = 0 }
    }
}
