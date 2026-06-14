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
                    Circle()
                        .fill(AppTheme.elevatedSurface)
                    Image(systemName: "person.fill")
                        .foregroundStyle(AppTheme.dynamicAccent)
                        .font(.system(size: size * 0.45))
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
