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
    @State private var dragTiltX: Double = 0
    @State private var dragTiltY: Double = 0
    @State private var palette: ArtworkPalette?

    /// Combined ambient + drag-driven tilt, clamped to a believable range
    /// so a fast drag can't flip the card past perspective limits.
    private var totalTiltX: Double {
        max(-22, min(22, tiltX + dragTiltX))
    }

    private var totalTiltY: Double {
        max(-22, min(22, tiltY + dragTiltY))
    }

    var body: some View {
        VStack(spacing: 6) {
            // Ambient glow — a soft palette-colored blur behind the card that
            // drifts opposite the tilt, suggesting the card is casting
            // colored light onto the surface behind it.
            ZStack {
                if let palette {
                    Circle()
                        .fill(palette.primary)
                        .frame(width: 300, height: 300)
                        .blur(radius: 70)
                        .opacity(0.35)
                        .offset(x: -totalTiltY * 1.5, y: totalTiltX * 1.5)
                    Circle()
                        .fill(palette.secondary)
                        .frame(width: 240, height: 240)
                        .blur(radius: 60)
                        .opacity(0.25)
                        .offset(x: totalTiltY * 1.2, y: -totalTiltX * 1.2)
                }

                cardStack
            }

            // Reflective surface beneath — tilts in sync with the card above
            // so the "glass shelf" perspective stays consistent with whatever
            // angle the user (or the ambient animation) leaves the card at.
            ArtworkReflectionView(song: song, size: 290, cornerRadius: 18)
                .environmentObject(library)
                .rotation3DEffect(.degrees(totalTiltX * 0.5), axis: (x: 1, y: 0, z: 0), perspective: 0.4)
                .rotation3DEffect(.degrees(totalTiltY * 0.5), axis: (x: 0, y: 1, z: 0), perspective: 0.4)
        }
        .frame(width: 300)
        .onAppear { updateAnimations(playing: isPlaying) }
        .onChange(of: isPlaying) { playing in updateAnimations(playing: playing) }
        .task(id: song?.id) { await loadPalette() }
        .animation(.easeInOut(duration: 1.2), value: palette)
    }

    private var cardStack: some View {
        VStack(spacing: 6) {
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
            // Holographic foil sheen — a rainbow-tinted gradient (built from
            // the artwork's palette) that slides and shifts hue with the
            // tilt direction, like light catching a foil-printed card.
            .overlay(
                AngularGradient(
                    colors: [
                        (palette?.primary ?? .white).opacity(0.5),
                        (palette?.secondary ?? .white).opacity(0.3),
                        .clear,
                        (palette?.primary ?? .white).opacity(0.4),
                    ],
                    center: .center
                )
                .hueRotation(.degrees((totalTiltX + totalTiltY) * 3))
                .blendMode(.colorDodge)
                .opacity(0.35)
                .offset(x: totalTiltY * 6, y: -totalTiltX * 6)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .allowsHitTesting(false)
            )
            // Specular highlight — a soft diagonal sheen that slides across the
            // card opposite the tilt direction, like light catching glass.
            .overlay(
                LinearGradient(
                    colors: [.clear, .white.opacity(0.16), .clear],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .rotationEffect(.degrees(20))
                .offset(x: totalTiltY * 6, y: -totalTiltX * 6)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .allowsHitTesting(false)
            )
            .shadow(color: .black.opacity(0.45), radius: 22, x: -totalTiltY * 1.4, y: totalTiltX * 1.4 + 14)
            .rotation3DEffect(.degrees(totalTiltX), axis: (x: 1, y: 0, z: 0), perspective: 0.4)
            .rotation3DEffect(.degrees(totalTiltY), axis: (x: 0, y: 1, z: 0), perspective: 0.4)
            // Drag to tilt — grab the card and tip it in 3D space; it springs
            // back to the ambient animation on release.
            .gesture(
                DragGesture()
                    .onChanged { value in
                        dragTiltX = max(-16, min(16, Double(-value.translation.height) / 10))
                        dragTiltY = max(-16, min(16, Double(value.translation.width) / 10))
                    }
                    .onEnded { _ in
                        withAnimation(.spring(response: 0.5, dampingFraction: 0.6)) {
                            dragTiltX = 0
                            dragTiltY = 0
                        }
                    }
            )
        }
        .frame(width: 300)
    }

    private func loadPalette() async {
        palette = await ArtworkPaletteLoader.palette(for: song, library: library)
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
