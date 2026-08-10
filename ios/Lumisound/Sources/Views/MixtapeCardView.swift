import SwiftUI

/// A shareable, designed cover card for any playlist — same "render a
/// themed card via ImageRenderer, share through the system sheet" pattern
/// `RewindView` already uses for its recap cards (reusing its
/// `RewindShareSheet` wrapper), just for a playlist's tracklist instead of
/// listening stats. Distinct from Collaborative Playlists' share-code
/// (a functional in-app invite mechanism, see `CollaborativePlaylistView`):
/// this is a purely aesthetic export meant for posting outside the app —
/// there's no code to redeem, no live data, just a picture.
struct MixtapeCardView: View {
    let playlist: Playlist

    @EnvironmentObject private var library: LibraryManager
    @State private var artworkImages: [UIImage] = []
    @State private var isLoadingArtwork = true
    @State private var shareImage: UIImage?
    @State private var showShare = false

    private var songs: [Song] { library.songs(for: playlist) }

    private var totalDuration: TimeInterval {
        songs.reduce(0) { $0 + $1.duration }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                card
                    .frame(maxWidth: 360)

                Button {
                    renderAndShare()
                } label: {
                    Label("Share Mixtape", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(AppTheme.dynamicAccent)
                .disabled(isLoadingArtwork)
            }
            .padding()
        }
        .navigationTitle("Mixtape Card")
        .navigationBarTitleDisplayMode(.inline)
        .background(GalleryBackgroundView().ignoresSafeArea())
        .task { await loadArtwork() }
        .sheet(isPresented: $showShare) {
            if let shareImage {
                RewindShareSheet(items: [shareImage])
            }
        }
    }

    private func loadArtwork() async {
        var images: [UIImage] = []
        for song in songs.prefix(4) {
            if let image = await ArtworkService.shared.loadArtwork(for: song) {
                images.append(image)
            }
        }
        artworkImages = images
        isLoadingArtwork = false
    }

    // MARK: - Card (also what gets rendered to an image)

    private var card: some View {
        VStack(alignment: .leading, spacing: 18) {
            coverArt

            VStack(alignment: .leading, spacing: 2) {
                Text(playlist.name)
                    .font(.system(size: 20, weight: .heavy))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                Text("\(songs.count) track\(songs.count == 1 ? "" : "s") · \(formattedTime(totalDuration))")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.75))
            }

            if !songs.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(songs.prefix(8).enumerated()), id: \.offset) { index, song in
                        HStack(spacing: 8) {
                            Text("\(index + 1)")
                                .font(.system(size: 12, weight: .bold, design: .rounded))
                                .foregroundStyle(.white.opacity(0.55))
                                .frame(width: 16, alignment: .leading)
                            Text("\(song.title) — \(song.artist)")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(.white)
                                .lineLimit(1)
                            Spacer()
                        }
                    }
                    if songs.count > 8 {
                        Text("+ \(songs.count - 8) more")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.white.opacity(0.6))
                    }
                }
            }

            Text("Lumisound")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.7))
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: [AppTheme.dynamicAccent, AppTheme.dynamicAccent.opacity(0.55), .black.opacity(0.85)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    @ViewBuilder
    private var coverArt: some View {
        if artworkImages.isEmpty {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [.white.opacity(0.3), .white.opacity(0.05)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    )
                )
                .frame(height: 140)
                .overlay(
                    Image(systemName: "music.note.list")
                        .font(.system(size: 32))
                        .foregroundStyle(.white.opacity(0.6))
                )
        } else {
            let columns = artworkImages.count >= 3 ? 2 : 1
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: columns), spacing: 2) {
                ForEach(Array(artworkImages.enumerated()), id: \.offset) { _, image in
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(1, contentMode: .fill)
                        .clipped()
                }
            }
            .frame(height: 140)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    private func formattedTime(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        if hours > 0 { return "\(hours)h \(minutes)m" }
        return "\(minutes)m"
    }

    @MainActor
    private func renderAndShare() {
        let renderer = ImageRenderer(content: card.frame(width: 360))
        renderer.scale = UIScreen.main.scale
        if let ui = renderer.uiImage {
            shareImage = ui
            showShare = true
        }
    }
}
