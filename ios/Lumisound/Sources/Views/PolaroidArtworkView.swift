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
            }
            .frame(width: photoSize, height: photoSize)
            .clipped()

            // Polaroid bottom strip with title
            ZStack {
                Color.white
                Text(song?.displayName ?? "Nothing Playing")
                    .font(.system(size: 14, weight: .regular, design: .serif))
                    .foregroundStyle(Color.black.opacity(0.75))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 10)
            }
            .frame(width: frameWidth, height: bottomPad)
        }
        .frame(width: frameWidth, height: photoSize + bottomPad)
        .background(Color.white)
        .padding(10)
        .background(Color.white)
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
