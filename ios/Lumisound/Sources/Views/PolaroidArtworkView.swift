import SwiftUI

struct PolaroidArtworkView: View {
    let song: Song?
    let isPlaying: Bool

    @EnvironmentObject private var library: LibraryManager

    private let frameWidth: CGFloat = 260
    private let photoSize:  CGFloat = 220
    private let bottomPad:  CGFloat = 52

    @State private var floating   = false
    @State private var rocking    = false
    @State private var glareOffset: CGFloat = -280

    var body: some View {
        VStack(spacing: 0) {
            // Photo area with glare sweep overlay
            ZStack {
                photoContent

                // Glare sweep — diagonal highlight that sweeps across the photo while playing
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0),
                        .init(color: .white.opacity(0.12), location: 0.45),
                        .init(color: .white.opacity(0.22), location: 0.5),
                        .init(color: .white.opacity(0.12), location: 0.55),
                        .init(color: .clear, location: 1),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .frame(width: photoSize * 1.4)
                .offset(x: glareOffset)
                .allowsHitTesting(false)

                // Film grain — a tiled noise texture that gives the photo a
                // subtle analog feel without any per-frame cost.
                FilmGrainOverlay()
                    .frame(width: photoSize, height: photoSize)
                    .blendMode(.overlay)
                    .opacity(0.18)
                    .allowsHitTesting(false)

                // Vintage color cast — a faint warm vignette over the photo
                RadialGradient(
                    colors: [.clear, Color(red: 0.55, green: 0.4, blue: 0.18).opacity(0.22)],
                    center: .center,
                    startRadius: photoSize * 0.35,
                    endRadius: photoSize * 0.72
                )
                .allowsHitTesting(false)
            }
            .frame(width: photoSize, height: photoSize)
            .clipped()

            // Polaroid bottom strip with handwritten-style caption
            ZStack {
                Color.white
                VStack(spacing: 1) {
                    Text(song?.displayName ?? "Nothing Playing")
                        .font(.custom("Bradley Hand", size: 18))
                        .foregroundStyle(Color.black.opacity(0.78))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    if let artist = song?.artistName, !artist.isEmpty {
                        Text(artist)
                            .font(.custom("Bradley Hand", size: 13))
                            .foregroundStyle(Color.black.opacity(0.5))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                }
                .multilineTextAlignment(.center)
                .padding(.horizontal, 10)
            }
            .frame(width: frameWidth, height: bottomPad)
        }
        .frame(width: frameWidth, height: photoSize + bottomPad)
        .background(Color.white)
        .padding(10)
        .background(Color.white)
        // Corner curl — a faint triangular shadow lifting the bottom-right
        // corner, like an aging print peeling slightly off its backing.
        .overlay(alignment: .bottomTrailing) {
            CornerCurlShape()
                .fill(
                    LinearGradient(
                        colors: [.clear, .black.opacity(0.18)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 38, height: 38)
                .allowsHitTesting(false)
        }
        // Rocking rotation — oscillates between -5° and -1° while playing, static -3° when paused
        .rotationEffect(.degrees(rocking ? -1.2 : -4.8))
        .animation(.easeInOut(duration: 3.2).repeatForever(autoreverses: true), value: rocking)
        // Dynamic shadow — shifts as the card floats and rocks
        .shadow(
            color: .black.opacity(0.45),
            radius: floating ? 28 : 14,
            x: floating ? 5 : 0,
            y: floating ? 16 : 8
        )
        .animation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true), value: floating)
        // Vertical float
        .offset(y: floating ? -8 : 0)
        .animation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true), value: floating)
        .onChange(of: isPlaying) { playing in
            updateAnimations(playing: playing)
        }
        .onAppear {
            updateAnimations(playing: isPlaying)
        }
    }

    @ViewBuilder
    private var photoContent: some View {
        if let song {
            ArtworkThumbnail(song: song, size: photoSize)
                .environmentObject(library)
        } else {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(AppTheme.surface)
                .frame(width: photoSize, height: photoSize)
                .overlay {
                    Image(systemName: "music.note")
                        .font(.system(size: 64, weight: .semibold))
                        .foregroundStyle(AppTheme.dynamicAccent)
                }
        }
    }

    private func updateAnimations(playing: Bool) {
        if playing {
            floating = true
            rocking = true
            startGlare()
        } else {
            withAnimation(.easeOut(duration: 0.5)) {
                floating = false
                rocking = false
            }
            withAnimation(.easeOut(duration: 0.3)) {
                glareOffset = -280
            }
        }
    }

    private func startGlare() {
        glareOffset = -280
        withAnimation(.linear(duration: 3.5).repeatForever(autoreverses: false)) {
            glareOffset = 320
        }
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

/// A static, tiled speckle pattern drawn once with `Canvas` to suggest
/// photo-paper grain. Deterministic (seeded) so it doesn't shimmer or cost
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
private struct SeededRandom {
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

// MARK: - CornerCurlShape

/// A simple right-triangle shape used as a faint shadow to suggest a lifted
/// photo corner.
struct CornerCurlShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}
