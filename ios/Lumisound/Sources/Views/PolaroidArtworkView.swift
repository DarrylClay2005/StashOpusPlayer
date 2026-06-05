import SwiftUI

// MARK: - PolaroidArtworkView
//
// Album art displayed in a white-bordered polaroid frame, slightly rotated,
// with the song title at the bottom in a serif/handwriting-style font.

struct PolaroidArtworkView: View {
    let song: Song?
    let isPlaying: Bool

    @EnvironmentObject private var library: LibraryManager

    private let frameWidth: CGFloat  = 260
    private let photoSize:  CGFloat  = 220
    private let bottomPad:  CGFloat  = 52

    var body: some View {
        VStack(spacing: 0) {
            // Photo area
            if let song {
                ArtworkThumbnail(song: song, size: photoSize)
                    .environmentObject(library)
            } else {
                placeholderPhoto
            }

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
        // White polaroid border
        .background(Color.white)
        .padding(10)
        .background(Color.white)
        // Slight tilt
        .rotationEffect(.degrees(-3))
        .shadow(color: .black.opacity(0.40), radius: 18, x: 0, y: 10)
        // Gentle float animation while playing
        .modifier(FloatModifier(isPlaying: isPlaying, amount: 4, speed: 2.4))
    }

    private var placeholderPhoto: some View {
        RoundedRectangle(cornerRadius: 4, style: .continuous)
            .fill(AppTheme.surface)
            .frame(width: photoSize, height: photoSize)
            .overlay {
                Image(systemName: "music.note")
                    .font(.system(size: 64, weight: .semibold))
                    .foregroundStyle(AppTheme.accent)
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
