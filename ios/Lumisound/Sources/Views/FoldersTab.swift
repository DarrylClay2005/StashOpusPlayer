import SwiftUI
import MediaPlayer
import UIKit

// MARK: - Folders Tab
//
// Groups imported songs by the first subdirectory of "Imported Music" that
// contains them. Unlike the Albums tab, grouping is done by filesystem path —
// every song inside a folder shows up here regardless of its album metadata tag.
// The actual grouping logic lives in `MusicFolderService.localFolderGroups(from:)`
// so `LibraryHubView`'s speed-dial folder tiles use the exact same folder set.

private typealias FolderEntry = MusicFolderService.LocalFolderGroup

struct FoldersTab: View {
    @EnvironmentObject private var library: LibraryManager
    @AppStorage("library_folders_columns") private var columns: Int = 2

    @State private var folders: [FolderEntry] = []

    private var gridColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 12), count: columns)
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
                .padding(.bottom, 190)
            }
        }
        .background(Color.clear.ignoresSafeArea())
        .task(id: library.allSongs.count) {
            folders = MusicFolderService.localFolderGroups(from: library.allSongs)
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

    // Custom, device-local folder cover art (see FolderCoverArtService) —
    // read once on appear/whenever this folder's identity changes rather
    // than as a plain computed property: `cover(for:)` does a dictionary
    // lookup (cheap) but also decodes+caches from disk on a cold cache
    // miss, which isn't free to repeat on every SwiftUI body pass for a
    // grid full of these cells. LocalFolderDetailView already shows
    // whatever custom cover is set for a folder; this grid never checked
    // for one at all, so a folder with a custom cover reverted to its
    // default (first song's artwork / folder glyph) the moment you backed
    // out to the grid.
    @State private var customCover: UIImage? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // GeometryReader sizes the artwork to the actual column width — like
            // SongGridCell, a hardcoded size here clips (3-column) or under-fills
            // (1-column) the cell depending on how many columns are selected.
            GeometryReader { geo in
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(AppTheme.surface)

                    if let customCover {
                        Image(uiImage: customCover)
                            .resizable()
                            .scaledToFill()
                            .frame(width: geo.size.width, height: geo.size.width)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    } else if let song = representativeSong {
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
        .onAppear {
            customCover = FolderCoverArtService.shared.cover(for: folder.dirURL)
        }
    }
}
