import SwiftUI

struct PlaylistsView: View {
    @EnvironmentObject private var library: LibraryManager

    @State private var showingCreateSheet = false
    @State private var newPlaylistName = ""

    var body: some View {
        List {
            if library.playlists.isEmpty {
                EmptyStateView(
                    icon: "music.note.list",
                    title: "No playlists",
                    message: "Tap the + button to create your first playlist."
                )
                .listRowBackground(Color.clear)
            } else {
                ForEach(library.playlists) { playlist in
                    NavigationLink {
                        PlaylistDetailView(playlist: playlist)
                    } label: {
                        PlaylistRow(playlist: playlist)
                    }
                    .listRowBackground(AppTheme.surface.opacity(0.5))
                }
                .onDelete { indexSet in
                    for index in indexSet {
                        library.deletePlaylist(library.playlists[index])
                    }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(AppTheme.background.ignoresSafeArea())
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    newPlaylistName = ""
                    showingCreateSheet = true
                } label: {
                    Image(systemName: "plus")
                }
                .tint(AppTheme.accent)
            }
        }
        .sheet(isPresented: $showingCreateSheet) {
            CreatePlaylistSheet(
                name: $newPlaylistName,
                onCreate: { name in
                    library.createPlaylist(name: name)
                    showingCreateSheet = false
                },
                onCancel: {
                    showingCreateSheet = false
                }
            )
        }
    }
}

// MARK: - Playlist Row

private struct PlaylistRow: View {
    let playlist: Playlist

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(AppTheme.elevatedSurface)
                Image(systemName: "music.note.list")
                    .foregroundStyle(AppTheme.accent)
                    .font(.system(size: 18))
            }
            .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 3) {
                Text(playlist.name)
                    .foregroundStyle(AppTheme.textPrimary)
                    .lineLimit(1)
                Text("\(playlist.songCount) \(playlist.songCount == 1 ? "song" : "songs")")
                    .font(.caption)
                    .foregroundStyle(AppTheme.textSecondary)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Create Playlist Sheet

private struct CreatePlaylistSheet: View {
    @Binding var name: String
    let onCreate: (String) -> Void
    let onCancel: () -> Void

    @FocusState private var isFocused: Bool

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Playlist Name") {
                    TextField("My Playlist", text: $name)
                        .focused($isFocused)
                        .autocorrectionDisabled()
                        .foregroundStyle(AppTheme.textPrimary)
                        .listRowBackground(AppTheme.surface)
                }
            }
            .scrollContentBackground(.hidden)
            .background(AppTheme.background.ignoresSafeArea())
            .navigationTitle("New Playlist")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                        .tint(AppTheme.textSecondary)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
                        onCreate(trimmed)
                    }
                    .disabled(!isValid)
                    .tint(AppTheme.accent)
                }
            }
            .onAppear { isFocused = true }
        }
    }
}
