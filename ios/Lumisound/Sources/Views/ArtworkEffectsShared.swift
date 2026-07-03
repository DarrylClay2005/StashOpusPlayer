import SwiftUI

// MARK: - ArtworkPaletteLoader (shared palette-loading helper)

/// Loads the dominant-color palette for a song's artwork, used by every Now
/// Playing artwork style for palette-driven glows/accents. Centralizes the
/// "use cached artwork if available, otherwise fetch it" + extraction logic
/// that was previously duplicated verbatim across nine artwork views.
enum ArtworkPaletteLoader {
    @MainActor
    static func palette(for song: Song?) async -> ArtworkPalette? {
        guard let song else { return nil }
        // Goes straight to the async path: a synchronous `LibraryManager`
        // lookup would read and decode the disk-cache JPEG on the MainActor,
        // hitching the UI on every track change. `loadArtwork`'s memory-cache
        // hit is just as fast, and its disk/remote fallbacks run off the main
        // thread.
        guard let image = await ArtworkService.shared.loadArtwork(for: song) else { return nil }
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

// MARK: - PressableButtonStyle

/// A button style that scales the label down slightly (and dims it) while
/// pressed, for tactile press feedback on transport/control buttons. Replaces
/// `.buttonStyle(.plain)` where a bit of physicality is wanted.
struct PressableButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.9 : 1.0)
            .opacity(configuration.isPressed ? 0.8 : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: configuration.isPressed)
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
