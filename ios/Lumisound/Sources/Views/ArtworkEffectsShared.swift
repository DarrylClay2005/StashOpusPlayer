import SwiftUI

// MARK: - ArtworkPaletteLoader (shared palette-loading helper)

/// Loads the dominant-color palette for a song's artwork, used by every Now
/// Playing artwork style for palette-driven glows/accents. Centralizes the
/// "use cached artwork if available, otherwise fetch it" + extraction logic
/// that was previously duplicated verbatim across nine artwork views.
enum ArtworkPaletteLoader {
    static func palette(for song: Song?, library: LibraryManager) async -> ArtworkPalette? {
        guard let song else { return nil }
        var image = library.artwork(for: song)
        if image == nil {
            image = await ArtworkService.shared.loadArtwork(for: song)
        }
        guard let image else { return nil }
        return ArtworkColorExtractor.palette(from: image)
    }
}

// MARK: - FloatModifier (shared utility for gentle vertical float)

struct FloatModifier: ViewModifier {
    let isPlaying: Bool
    let amount: CGFloat
    let speed: Double

    @State private var floating = false

    func body(content: Content) -> some View {
        content
            .offset(y: floating ? -amount : 0)
            .onChange(of: isPlaying) { playing in
                if playing {
                    withAnimation(.easeInOut(duration: speed).repeatForever(autoreverses: true)) {
                        floating = true
                    }
                } else {
                    withAnimation(.easeOut(duration: 0.4)) {
                        floating = false
                    }
                }
            }
            .onAppear {
                if isPlaying {
                    withAnimation(.easeInOut(duration: speed).repeatForever(autoreverses: true)) {
                        floating = true
                    }
                }
            }
    }
}

// MARK: - FilmGrainOverlay

/// A static, tiled speckle pattern drawn once with `Canvas` to suggest paper
/// or photo grain. Deterministic (seeded) so it doesn't shimmer or cost
/// anything per-frame — drawn a single time and left in place.
struct FilmGrainOverlay: View {
    var body: some View {
        Canvas { context, size in
            var generator = SeededRandom(seed: 1_337)
            let dotCount = Int((size.width * size.height) / 14)
            for _ in 0..<dotCount {
                let x = generator.nextDouble() * size.width
                let y = generator.nextDouble() * size.height
                let alpha = 0.05 + generator.nextDouble() * 0.18
                let dotSize = generator.nextDouble() < 0.5 ? 0.6 : 1.1
                let rect = CGRect(x: x, y: y, width: dotSize, height: dotSize)
                context.fill(Path(ellipseIn: rect), with: .color(.white.opacity(alpha)))
            }
        }
        .drawingGroup()
    }
}

/// A tiny deterministic PRNG (xorshift) used to lay out grain dots without
/// pulling in `GameplayKit` or reseeding `SystemRandomNumberGenerator` on
/// every redraw.
struct SeededRandom {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed == 0 ? 0xdead_beef : seed
    }

    mutating func nextDouble() -> Double {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return Double(state % 1_000_000) / 1_000_000
    }
}
