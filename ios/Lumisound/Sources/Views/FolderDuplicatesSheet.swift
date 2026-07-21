import SwiftUI

// MARK: - FolderDuplicatesSheet
//
// Folder-scoped counterpart to DuplicateFilesView (Settings → Duplicate
// Finder): runs the exact same three-pass matching logic
// (`DuplicateFinderService.findDuplicateGroups(among:)` — same source-track
// ID -> acoustic fingerprint -> title+artist fallback pipeline) but only
// over the songs already loaded for a single LocalFolderDetailView, and
// deliberately does NOT touch `DuplicateFinderService.shared`'s published
// `duplicateGroups`/`lastScanDate` — those belong to the full-library scan,
// and a folder-scoped scan here must never clobber them. Result state
// (`groups`) lives entirely in this view instead.
//
// Row presentation mirrors `DuplicateFilesView.duplicateRow` exactly (same
// `SongRow` + trailing trash/"Apple Music" badge) so a user who's used the
// full-library scanner sees a familiar screen here.

struct FolderDuplicatesSheet: View {
    let songs: [Song]

    @EnvironmentObject private var library: LibraryManager
    @Environment(\.dismiss) private var dismiss

    @State private var groups: [DuplicateGroup] = []
    @State private var isScanning = false
    @State private var hasScanned = false
    @State private var pendingDeletion: (songID: String, title: String)?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        Label("Songs in Folder", systemImage: "music.note")
                            .foregroundStyle(AppTheme.textPrimary)
                        Spacer()
                        Text("\(songs.count)")
                            .font(AppTheme.monoFont(size: 14))
                            .foregroundStyle(AppTheme.textSecondary)
                    }

                    Button {
                        Task { await runScan() }
                    } label: {
                        HStack {
                            Label(hasScanned ? "Scan Again" : "Scan This Folder", systemImage: "arrow.clockwise")
                                .foregroundStyle(AppTheme.dynamicAccent)
                            Spacer()
                            if isScanning {
                                ProgressView().tint(AppTheme.dynamicAccent)
                            }
                        }
                    }
                    .disabled(isScanning || songs.count < 2)
                } footer: {
                    Text("Checks tracks in this folder for duplicates: same source download, acoustically identical audio, or matching title & artist. Deleting a copy removes its file from disk.")
                        .font(AppTheme.bodyFont(size: 12))
                        .foregroundStyle(AppTheme.textSecondary)
                }
                .listRowBackground(AppTheme.surface)

                if !groups.isEmpty {
                    ForEach(groups) { group in
                        Section {
                            ForEach(group.songs) { song in
                                duplicateRow(song: song)
                            }
                        } header: {
                            sectionHeader("\(group.songs.count) Copies — \(group.reason.label)")
                        }
                        .listRowBackground(AppTheme.surface)
                    }
                } else if hasScanned && !isScanning {
                    Section {
                        VStack(spacing: 10) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 40))
                                .foregroundStyle(AppTheme.success)
                            Text("No duplicates found")
                                .font(AppTheme.headlineFont(size: 15))
                                .foregroundStyle(AppTheme.textPrimary)
                            Text("Every track in this folder appears to be unique.")
                                .font(AppTheme.bodyFont(size: 13))
                                .foregroundStyle(AppTheme.textSecondary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 20)
                        .listRowBackground(Color.clear)
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(GalleryBackgroundView().ignoresSafeArea())
            .navigationTitle("Folder Duplicates")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                        .tint(AppTheme.dynamicAccent)
                }
            }
            .confirmationDialog(
                "Delete This Copy?",
                isPresented: Binding(
                    get: { pendingDeletion != nil },
                    set: { if !$0 { pendingDeletion = nil } }
                ),
                titleVisibility: .visible
            ) {
                if let pending = pendingDeletion {
                    Button("Delete \"\(pending.title)\"", role: .destructive) {
                        library.removeImportedSong(id: pending.songID)
                        groups = groups.compactMap { group in
                            var remaining = group.songs
                            remaining.removeAll { $0.id == pending.songID }
                            guard remaining.count > 1 else { return nil }
                            return DuplicateGroup(id: group.id, songs: remaining, reason: group.reason)
                        }
                        pendingDeletion = nil
                    }
                    Button("Cancel", role: .cancel) { pendingDeletion = nil }
                }
            } message: {
                Text("This permanently deletes the downloaded file from your device. This action cannot be undone.")
            }
        }
    }

    // MARK: - Scan

    private func runScan() async {
        isScanning = true
        groups = await DuplicateFinderService.findDuplicateGroups(among: songs)
        hasScanned = true
        isScanning = false
    }

    // MARK: - Row

    private func duplicateRow(song: Song) -> some View {
        let removable = song.persistentID == nil && song.url != nil

        return HStack(spacing: 0) {
            SongRow(song: song, isCurrent: false, subtitle: rowSubtitle(for: song))

            if removable {
                Button {
                    pendingDeletion = (songID: song.id, title: song.displayName)
                } label: {
                    Image(systemName: "trash")
                        .foregroundStyle(AppTheme.error)
                        .font(.system(size: 16))
                        .padding(.leading, 12)
                }
                .buttonStyle(.plain)
            } else {
                Text("Apple Music")
                    .font(AppTheme.bodyFont(size: 11))
                    .foregroundStyle(AppTheme.textSecondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(AppTheme.elevatedSurface, in: Capsule())
                    .padding(.leading, 12)
            }
        }
    }

    private func rowSubtitle(for song: Song) -> String {
        var parts = [song.artistName, song.albumName, song.durationText]
        if let sourceID = song.sourceTrackID, !sourceID.isEmpty {
            parts.append(sourceID)
        }
        return parts.filter { !$0.isEmpty }.joined(separator: " · ")
    }

    private func sectionHeader(_ text: String) -> some View {
        Text(text.uppercased())
            .font(AppTheme.bodyFont(size: 11))
            .foregroundStyle(AppTheme.textSecondary)
            .kerning(0.8)
    }
}
