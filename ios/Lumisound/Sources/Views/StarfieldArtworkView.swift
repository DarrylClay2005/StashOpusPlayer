import SwiftUI

// MARK: - StarfieldArtworkView — "Cosmos"
//
// The cover floating in deep space: glowing nebula clouds and a rotating field
// of bright, varied stars.
struct StarfieldArtworkView: View {
    let song: Song?
    let isPlaying: Bool

    @EnvironmentObject private var library: LibraryManager
    @State private var palette: ArtworkPalette?
    @State private var rotate = false
    @State private var twinkle = false

    private var c1: Color { palette?.primary ?? AppTheme.dynamicAccent }
    private var c2: Color { palette?.secondary ?? Color(hue: 0.78, saturation: 0.7, brightness: 0.95) }

    // Deterministic star positions/sizes within a 320×320 field.
    private let stars: [(x: CGFloat, y: CGFloat, s: CGFloat)] = (0..<90).map { i in
        let x = CGFloat((i &* 73) % 300) + 10
        let y = CGFloat((i &* 151) % 300) + 10
        let s = CGFloat(1 + (i % 4))
        return (x, y, s)
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 26, style: .continuous).fill(Color(red: 0.02, green: 0.02, blue: 0.06))

            // Nebula clouds.
            Ellipse().fill(c1).frame(width: 260, height: 190).blur(radius: 55).opacity(0.5)
                .offset(x: -50, y: -50).blendMode(.screen)
            Ellipse().fill(c2).frame(width: 230, height: 170).blur(radius: 55).opacity(0.45)
                .offset(x: 60, y: 70).blendMode(.screen)

            // Rotating, twinkling star field.
            ZStack {
                ForEach(Array(stars.enumerated()), id: \.offset) { _, st in
                    Circle()
                        .fill(.white)
                        .frame(width: st.s, height: st.s)
                        .shadow(color: .white.opacity(0.8), radius: st.s > 3 ? 3 : 0)
                        .position(x: st.x, y: st.y)
                }
            }
            .frame(width: 320, height: 320)
            .rotationEffect(.degrees(rotate ? 360 : 0))
            .opacity(twinkle ? 1.0 : 0.55)

            StyleCover(song: song, size: 230, cornerRadius: 18)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(.white.opacity(0.2), lineWidth: 1))
                .shadow(color: .black.opacity(0.7), radius: 30)
                .shadow(color: c1.opacity(0.4), radius: 24)
        }
        .frame(width: 320, height: 320)
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .modifier(FloatModifier(isPlaying: isPlaying, amount: 5, speed: 3.4))
        .onAppear {
            withAnimation(.linear(duration: 70).repeatForever(autoreverses: false)) { rotate = true }
            withAnimation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true)) { twinkle = true }
        }
        .task(id: song?.id) { palette = await ArtworkPaletteLoader.palette(for: song, library: library) }
        .animation(.easeInOut(duration: 1.0), value: palette)
    }
}
