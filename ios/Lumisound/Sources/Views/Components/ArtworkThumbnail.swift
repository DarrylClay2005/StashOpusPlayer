import SwiftUI
import UIKit

struct ArtworkThumbnail: View {
    let song: Song
    let size: CGFloat

    @EnvironmentObject private var library: LibraryManager
    @State private var image: UIImage? = nil

    var body: some View {
        ZStack(alignment: .bottom) {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size, height: size)
                    .clipped()

                // Gradient overlay on bottom third
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color.black.opacity(0.0),
                        Color.black.opacity(0.45)
                    ]),
                    startPoint: .center,
                    endPoint: .bottom
                )
                .frame(height: size / 3)
            } else {
                RoundedRectangle(cornerRadius: max(4, size * 0.1), style: .continuous)
                    .fill(AppTheme.surface)
                    .overlay {
                        Image(systemName: "music.note")
                            .font(.system(size: size * 0.35, weight: .medium))
                            .foregroundStyle(AppTheme.dynamicAccent)
                    }
                    .frame(width: size, height: size)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: max(4, size * 0.1), style: .continuous))
        .task(id: song.id) {
            // Try synchronous cache first
            if let cached = library.artwork(for: song) {
                image = cached
                return
            }
            // Not yet cached — load asynchronously via ArtworkService
            let loaded = await ArtworkService.shared.loadArtwork(for: song)
            image = loaded
        }
    }
}
