import SwiftUI
import UIKit

/// Identifies one `ArtworkThumbnail.task` request. A plain `Equatable` struct
/// instead of an interpolated `"\(song.id)#\(pixelBucket)"` String — SwiftUI
/// re-evaluates `body` (and this id) on every scroll/state invalidation for
/// every visible row, and a formatted-String id would heap-allocate on each
/// of those evaluations just to be diffed against the previous value.
private struct ThumbnailRequestID: Equatable {
    let songID: String
    let pixelBucket: Int
}

struct ArtworkThumbnail: View {
    let song: Song
    let size: CGFloat

    @Environment(\.displayScale) private var displayScale
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
                    .overlay(
                        ShimmerOverlay()
                            .clipShape(RoundedRectangle(cornerRadius: max(4, size * 0.1), style: .continuous))
                    )
                    .frame(width: size, height: size)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: max(4, size * 0.1), style: .continuous))
        // Keyed on size as well as song: grid cells size this view from a
        // GeometryReader, so the width can settle after the first layout pass —
        // without the size in the id, a thumbnail fetched for the initial
        // (smaller) size would never be upgraded.
        .task(id: ThumbnailRequestID(songID: song.id, pixelBucket: Int(size * displayScale))) {
            // Load at (bucketed) display size, not the full 1200px cache size —
            // a 44pt row only needs ~132 physical px, and the thumbnail path
            // keeps disk reads/decodes off the main thread. The synchronous
            // memory-cache check avoids a placeholder flash for art that's
            // already been rendered once.
            let pixelSize = size * displayScale
            if let cached = ArtworkService.shared.thumbnail(for: song, pixelSize: pixelSize) {
                image = cached
                return
            }
            // Clear rather than leave the previous song's art on screen: since
            // SwiftUI can reuse this view's identity for a different row while
            // scrolling, a stale `image` would otherwise display under the
            // new song's row for the duration of the async load below.
            image = nil
            image = await ArtworkService.shared.loadThumbnail(for: song, pixelSize: pixelSize)
        }
    }
}
