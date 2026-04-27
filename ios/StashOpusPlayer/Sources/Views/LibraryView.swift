import SwiftUI
import UniformTypeIdentifiers

struct LibraryView: View {
    @EnvironmentObject private var library: MusicLibraryStore
    @EnvironmentObject private var player: AudioPlayerManager
    @State private var searchText = ""
    @State private var isImporterPresented = false

    private var filteredSongs: [Song] {
        guard !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return library.allSongs
        }
        return library.allSongs.filter { song in
            song.displayName.localizedCaseInsensitiveContains(searchText)
                || song.artistName.localizedCaseInsensitiveContains(searchText)
                || song.albumName.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                if let error = library.errorMessage {
                    Text(error)
                        .foregroundStyle(AppTheme.warning)
                }

                if filteredSongs.isEmpty {
                    EmptyLibraryView(isScanning: library.isScanning)
                        .listRowBackground(Color.clear)
                } else {
                    ForEach(filteredSongs) { song in
                        Button {
                            player.play(song: song, in: filteredSongs)
                        } label: {
                            SongRow(song: song, isCurrent: player.currentSong?.id == song.id)
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(AppTheme.background)
            .navigationTitle("Library")
            .searchable(text: $searchText, prompt: "Search songs, artists, albums")
            .toolbar {
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    Button {
                        library.scanMediaLibrary()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(library.isScanning)

                    Button {
                        isImporterPresented = true
                    } label: {
                        Image(systemName: "square.and.arrow.down")
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                MiniPlayerBar()
            }
            .fileImporter(
                isPresented: $isImporterPresented,
                allowedContentTypes: [.audio],
                allowsMultipleSelection: true
            ) { result in
                if case .success(let urls) = result {
                    library.importFiles(urls: urls)
                }
            }
            .onAppear {
                if library.allSongs.isEmpty {
                    library.requestAccessAndScan()
                }
            }
        }
    }
}

private struct EmptyLibraryView: View {
    let isScanning: Bool

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: isScanning ? "waveform" : "music.note")
                .font(.system(size: 42, weight: .semibold))
                .foregroundStyle(AppTheme.accent)

            Text(isScanning ? "Scanning library" : "No songs yet")
                .font(.headline)

            Text("Import audio files or grant media-library access from Settings.")
                .font(.subheadline)
                .foregroundStyle(AppTheme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
    }
}

struct SongRow: View {
    let song: Song
    let isCurrent: Bool

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isCurrent ? AppTheme.accent : AppTheme.elevatedSurface)
                Image(systemName: isCurrent ? "waveform" : "music.note")
                    .foregroundStyle(AppTheme.textPrimary)
            }
            .frame(width: 46, height: 46)

            VStack(alignment: .leading, spacing: 3) {
                Text(song.displayName)
                    .foregroundStyle(AppTheme.textPrimary)
                    .lineLimit(1)
                Text("\(song.artistName) - \(song.albumName)")
                    .font(.caption)
                    .foregroundStyle(AppTheme.textSecondary)
                    .lineLimit(1)
            }

            Spacer()

            Text(song.durationText)
                .font(.caption)
                .foregroundStyle(AppTheme.textSecondary)
        }
        .contentShape(Rectangle())
        .padding(.vertical, 4)
    }
}
