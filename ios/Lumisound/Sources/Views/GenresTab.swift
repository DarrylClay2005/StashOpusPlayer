import SwiftUI
import MediaPlayer

// MARK: - Genres Tab

struct GenresTab: View {
    @EnvironmentObject private var library: LibraryManager
    @EnvironmentObject private var player: AudioPlayerManager

    var body: some View {
        List {
            if library.genres.isEmpty {
                EmptyStateView(icon: "music.note.list", title: "No genres", message: "Add music to see genres here.")
                    .listRowBackground(Color.clear)
            } else {
                ForEach(library.genres, id: \.self) { genre in
                    Button {
                        let songs = library.songs(inGenre: genre)
                        player.setQueue(songs, startIndex: 0, autoplay: true)
                    } label: {
                        GenreRow(genre: genre)
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(AppTheme.surface.opacity(0.5))
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }
}

private struct GenreRow: View {
    let genre: String
    @EnvironmentObject private var library: LibraryManager

    private var songCount: Int {
        library.songs(inGenre: genre).count
    }

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(AppTheme.elevatedSurface)
                Image(systemName: "music.note.list")
                    .foregroundStyle(AppTheme.dynamicAccent)
                    .font(.system(size: 16))
            }
            .frame(width: 40, height: 40)

            VStack(alignment: .leading, spacing: 2) {
                Text(genre)
                    .foregroundStyle(AppTheme.textPrimary)
                    .lineLimit(1)
                Text("\(songCount) \(songCount == 1 ? "song" : "songs")")
                    .font(.caption)
                    .foregroundStyle(AppTheme.textSecondary)
            }

            Spacer()

            Image(systemName: "play.circle.fill")
                .font(.system(size: 22))
                .foregroundStyle(AppTheme.dynamicAccent)
        }
        .padding(.vertical, 4)
    }
}
