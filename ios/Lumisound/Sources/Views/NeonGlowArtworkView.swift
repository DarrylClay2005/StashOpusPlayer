import SwiftUI

struct NeonGlowArtworkView: View {
    let song: Song?
    let isPlaying: Bool
    @EnvironmentObject private var library: LibraryManager

    @State private var glowPhase: Double = 0

    var body: some View {
        ZStack {
            ForEach(0..<3) { i in
                let hue = (glowPhase + Double(i) * 0.33).truncatingRemainder(dividingBy: 1)
                Circle()
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color(hue: hue, saturation: 1, brightness: 1),
                                Color(hue: (hue + 0.12).truncatingRemainder(dividingBy: 1), saturation: 0.8, brightness: 1)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 2
                    )
                    .frame(width: CGFloat(280 - i * 22), height: CGFloat(280 - i * 22))
                    .blur(radius: 6)
                    .opacity(0.55)
            }

            if let song {
                ArtworkThumbnail(song: song, size: 218)
                    .clipShape(Circle())
                    .overlay(
                        Circle()
                            .stroke(
                                LinearGradient(
                                    colors: [
                                        Color(hue: glowPhase, saturation: 1, brightness: 1),
                                        Color(hue: (glowPhase + 0.5).truncatingRemainder(dividingBy: 1), saturation: 1, brightness: 1)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 3
                            )
                    )
                    .shadow(
                        color: Color(hue: glowPhase, saturation: 1, brightness: 1).opacity(0.45),
                        radius: 22, x: 0, y: 0
                    )
            } else {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color(hue: glowPhase, saturation: 1, brightness: 0.8),
                                Color(hue: (glowPhase + 0.35).truncatingRemainder(dividingBy: 1), saturation: 0.8, brightness: 0.35)
                            ],
                            center: .center,
                            startRadius: 20,
                            endRadius: 110
                        )
                    )
                    .frame(width: 218, height: 218)
                    .overlay {
                        Image(systemName: "music.note")
                            .font(.system(size: 60, weight: .semibold))
                            .foregroundStyle(.white)
                    }
            }
        }
        .frame(width: 300, height: 300)
        .onAppear {
            withAnimation(.linear(duration: 4).repeatForever(autoreverses: false)) {
                glowPhase = 1
            }
        }
    }
}
