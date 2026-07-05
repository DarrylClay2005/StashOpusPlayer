import SwiftUI
import MediaPlayer

// MARK: - Folders Tab
//
// Groups imported songs by the first subdirectory of "Imported Music" that
// contains them. Unlike the Albums tab, grouping is done by filesystem path —
// every song inside a folder shows up here regardless of its album metadata tag.

private struct FolderEntry: Identifiable {
    let id: String        // folder name (unique within Imported Music)
    let dirURL: URL
    let songs: [Song]
}

struct FoldersTab: View {
    @EnvironmentObject private var library: LibraryManager
    @AppStorage("library_folders_columns") private var columns: Int = 2

    @State private var folders: [FolderEntry] = []

    private var gridColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 12), count: columns)
    }

    /// Groups allSongs by their top-level subdirectory under "Imported Music".
    /// Computed off the render path (see `.task(id:)` below) so large libraries
    /// don't re-run this O(n) grouping/sort on every body evaluation.
    private func computeFolders() -> [FolderEntry] {
        guard let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return []
        }
        let importDir = docs.appendingPathComponent("Imported Music").standardizedFileURL
        let importPath = importDir.path

        var groups: [String: (url: URL, songs: [Song])] = [:]
        for song in library.allSongs {
            guard let url = song.url else { continue }
            let songPath = url.standardizedFileURL.path
            guard songPath.hasPrefix(importPath + "/") else { continue }
            // Path after "Imported Music/"
            let remainder = String(songPath.dropFirst(importPath.count + 1))
            let parts = remainder.split(separator: "/", maxSplits: 1)
            guard parts.count >= 2 else { continue }   // skip root-level files
            let name = String(parts[0])
            if groups[name] == nil {
                groups[name] = (importDir.appendingPathComponent(name), [])
            }
            groups[name]!.songs.append(song)
        }

        return groups
            .sorted { $0.key.localizedCaseInsensitiveCompare($1.key) == .orderedAscending }
            .map { FolderEntry(id: $0.key, dirURL: $0.value.url, songs: $0.value.songs) }
    }

    var body: some View {
        ScrollView {
            if folders.isEmpty {
                EmptyStateView(
                    icon: "folder",
                    title: "No folders",
                    message: "Create subfolders inside \"Imported Music\" in the Files app to organise your tracks."
                )
                .padding(.top, 60)
            } else {
                LazyVGrid(columns: gridColumns, spacing: 16) {
                    ForEach(folders) { folder in
                        NavigationLink {
                            LocalFolderDetailView(folderName: folder.id, folderURL: folder.dirURL)
                        } label: {
                            FolderGridCell(folder: folder)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                // Extra clearance below the last row — see SongsTab's
                // identical fix.
                .padding(.bottom, 120)
            }
        }
        .background(Color.clear.ignoresSafeArea())
        .task(id: library.allSongs.count) {
            folders = computeFolders()
        }
        .toolbar {
            // Mirrors SongsTab's column-toggle buttons (rather than a Menu) so
            // switching the Folders layout works the same, directly-tappable way.
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                Button {
                    columns = 1
                } label: {
                    Image(systemName: "rectangle.grid.1x2")
                        .foregroundStyle(columns == 1 ? AppTheme.dynamicAccent : AppTheme.textSecondary)
                }
                .buttonStyle(.plain)

                Button {
                    columns = 2
                } label: {
                    Image(systemName: "square.grid.2x2")
                        .foregroundStyle(columns == 2 ? AppTheme.dynamicAccent : AppTheme.textSecondary)
                }
                .buttonStyle(.plain)

                Button {
                    columns = 3
                } label: {
                    Image(systemName: "square.grid.3x3")
                        .foregroundStyle(columns == 3 ? AppTheme.dynamicAccent : AppTheme.textSecondary)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

private struct FolderGridCell: View {
    let folder: FolderEntry

    private var representativeSong: Song? { folder.songs.first }
    private var trackCount: Int { folder.songs.count }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // GeometryReader sizes the artwork to the actual column width — like
            // SongGridCell, a hardcoded size here clips (3-column) or under-fills
            // (1-column) the cell depending on how many columns are selected.
            GeometryReader { geo in
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(AppTheme.surface)

                    if let song = representativeSong {
                        ArtworkThumbnail(song: song, size: geo.size.width)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    } else {
                        Image(systemName: "folder.fill")
                            .font(.system(size: geo.size.width * 0.25))
                            .foregroundStyle(AppTheme.dynamicAccent)
                    }

                    // Folder badge overlay
                    VStack {
                        Spacer()
                        HStack {
                            Image(systemName: "folder.fill")
                                .font(.caption2)
                            Spacer()
                        }
                        .padding(6)
                        .adaptiveGlass(in: Rectangle())
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
            }
            .frame(maxWidth: .infinity)
            .aspectRatio(1, contentMode: .fit)

            VStack(alignment: .leading, spacing: 2) {
                Text(folder.id)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.textPrimary)
                    .lineLimit(2)

                Text("\(trackCount) \(trackCount == 1 ? "track" : "tracks")")
                    .font(.caption2)
                    .foregroundStyle(AppTheme.textSecondary)
            }
            .padding(.horizontal, 2)
        }
    }
}
