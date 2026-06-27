import SwiftUI
import UIKit

/// Displays an artist's real profile picture (fetched via `ArtistImageService`
/// from Deezer's public artist search) at the requested size, falling back to
/// a generic accent-tinted person icon if no photo is found.
///
/// Deliberately does NOT fall back to a track's album art — showing the cover
/// of whichever song happens to come first for an artist isn't the artist's
/// picture, which is the whole point of this component.
struct ArtistAvatar: View {
    let artist: String
    let size: CGFloat
    /// Corner radius for the artwork shape. Defaults to a circle (size / 2).
    var cornerRadius: CGFloat? = nil

    @State private var image: UIImage? = nil

    private var radius: CGFloat { cornerRadius ?? size / 2 }

    /// First letter/number of the artist name, for the placeholder monogram.
    private var monogram: String {
        guard let first = artist.trimmingCharacters(in: .whitespacesAndNewlines)
            .first(where: { $0.isLetter || $0.isNumber }) else { return "♪" }
        return String(first).uppercased()
    }

    /// A stable (launch-independent) gradient derived from the artist name, so
    /// each artist gets a consistent, distinct colour — far more modern than the
    /// old grey-circle + green person glyph.
    private var monogramColors: [Color] {
        var hash = 5381
        for byte in artist.utf8 { hash = ((hash << 5) &+ hash) &+ Int(byte) }
        let hue = Double(abs(hash) % 360) / 360.0
        return [
            Color(hue: hue, saturation: 0.55, brightness: 0.78),
            Color(hue: (hue + 0.08).truncatingRemainder(dividingBy: 1.0), saturation: 0.68, brightness: 0.52),
        ]
    }

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size, height: size)
                    .clipped()
            } else {
                ZStack {
                    LinearGradient(
                        colors: monogramColors,
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    Text(monogram)
                        .font(.system(size: size * 0.42, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.95))
                        .minimumScaleFactor(0.5)
                }
                .frame(width: size, height: size)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        .task(id: artist) {
            if let cached = ArtistImageService.shared.cachedImage(for: artist) {
                image = cached
                return
            }
            image = await ArtistImageService.shared.loadImage(for: artist)
        }
    }
}
