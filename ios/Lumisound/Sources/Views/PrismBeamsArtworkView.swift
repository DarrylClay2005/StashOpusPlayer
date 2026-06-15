import SwiftUI

// MARK: - PrismBeamsArtworkView
//
// A crisp square cover sits at the center of slowly rotating light beams —
// thin gradient capsules radiating outward, colored from the artwork's
// palette — with a faint chromatic-fringe border suggesting light splitting
// through glass.

struct PrismBeamsArtworkView: View {
    let song: Song?
    let isPlaying: Bool

    @EnvironmentObject private var library: LibraryManager

    @State private var rotation: Double = 0
    @State private var glow = false
    @State private var palette: ArtworkPalette?

    private let artSize: CGFloat = 210
    private let beamLength: CGFloat = 80
    private let beamCount = 8

    var body: some View {
        ZStack {
            beams
                .frame(width: artSize + beamLength * 2, height: artSize + beamLength * 2)
                .rotationEffect(.degrees(rotation))

            centralArt
        }
        .frame(width: artSize + beamLength * 2, height: artSize + beamLength * 2)
        .onAppear {
            if isPlaying { startAnimations() }
        }
        .onChange(of: isPlaying) { playing in
            if playing { startAnimations() } else { stopAnimations() }
        }
        .task(id: song?.id) {
            await loadPalette()
        }
        .animation(.easeInOut(duration: 1.2), value: palette)
    }

    private var beams: some View {
        ZStack {
            ForEach(0..<beamCount, id: \.self) { i in
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [beamColor(index: i), .clear],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: beamLength, height: 2.5)
                    .offset(x: artSize / 2 + beamLength / 2 - 6)
                    .rotationEffect(.degrees(Double(i) * (360.0 / Double(beamCount))))
                    .blur(radius: 1.5)
                    .opacity(isPlaying ? 0.75 : 0.3)
            }
        }
    }

    private func beamColor(index: Int) -> Color {
        index % 2 == 0
            ? (palette?.primary ?? AppTheme.dynamicAccent)
            : (palette?.secondary ?? AppTheme.accentSoft)
    }

    private var centralArt: some View {
        Group {
            if let song {
                ArtworkThumbnail(song: song, size: artSize)
                    .environmentObject(library)
            } else {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
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
                            .font(.system(size: 60, weight: .semibold))
                            .foregroundStyle(AppTheme.dynamicAccent)
                    }
            }
        }
        .frame(width: artSize, height: artSize)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        // Chromatic-fringe border — two offset, tinted strokes peeking out
        // from behind the crisp white border, like a prism splitting light
        // at the card's edge.
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke((palette?.primary ?? .cyan).opacity(0.5), lineWidth: 1.5)
                .offset(x: -1.5, y: 0)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke((palette?.secondary ?? .pink).opacity(0.5), lineWidth: 1.5)
                .offset(x: 1.5, y: 0)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(.white.opacity(0.18), lineWidth: 1)
        )
        .shadow(
            color: (palette?.primary ?? AppTheme.dynamicAccent).opacity(glow ? 0.5 : 0.2),
            radius: glow ? 24 : 12, x: 0, y: 0
        )
        .animation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true), value: glow)
    }

    private func loadPalette() async {
        palette = await ArtworkPaletteLoader.palette(for: song, library: library)
    }

    private func startAnimations() {
        glow = true
        withAnimation(.linear(duration: 60).repeatForever(autoreverses: false)) {
            rotation = 360
        }
    }

    private func stopAnimations() {
        glow = false
        withAnimation(.easeOut(duration: 0.8)) {
            rotation = 0
        }
    }
}
