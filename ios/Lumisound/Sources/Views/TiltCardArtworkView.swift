import SwiftUI

// MARK: - TiltCardArtworkView — "Depth Parallax"
//
// The cover as a 3D card gently tilting on both axes, with a glare that tracks
// the tilt and a deep drop shadow — a tactile, parallax depth effect.
struct TiltCardArtworkView: View {
    let song: Song?
    let isPlaying: Bool

    @EnvironmentObject private var library: LibraryManager
    @State private var tilt = false

    private let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)

    var body: some View {
        StyleCover(song: song, size: 290, cornerRadius: 22)
            .clipShape(shape)
            .overlay(
                LinearGradient(colors: [.white.opacity(0.35), .clear, .white.opacity(0.12)],
                               startPoint: tilt ? .topLeading : .bottomTrailing,
                               endPoint: tilt ? .bottomTrailing : .topLeading)
                    .blendMode(.plusLighter)
                    .clipShape(shape)
            )
            .overlay(shape.stroke(.white.opacity(0.18), lineWidth: 1))
            .frame(width: 290, height: 290)
            .rotation3DEffect(.degrees(tilt ? 9 : -9), axis: (x: 1, y: 0, z: 0), perspective: 0.5)
            .rotation3DEffect(.degrees(tilt ? -9 : 9), axis: (x: 0, y: 1, z: 0), perspective: 0.5)
            .shadow(color: .black.opacity(0.5), radius: 30, x: tilt ? 14 : -14, y: 20)
            .onAppear {
                withAnimation(.easeInOut(duration: 3.6).repeatForever(autoreverses: true)) { tilt = true }
            }
    }
}
