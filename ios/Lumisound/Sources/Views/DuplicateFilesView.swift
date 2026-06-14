import SwiftUI

// MARK: - DuplicateFilesView

struct DuplicateFilesView: View {

    @EnvironmentObject private var library: LibraryManager
    @StateObject private var service = DuplicateFinderService.shared

    @State private var pendingDeletion: (songID: String, title: String)?
    @State private var showDeleteAllConfirm = false

    // MARK: Body

    var body: some View {
        List {
            // Status section
            Section {
                HStack {
                    Label("Last Scan", systemImage: "clock")
                        .foregroundStyle(AppTheme.textPrimary)
                    Spacer()
                    if let date = service.lastScanDate {
                        Text(date, style: .relative)
                            .font(AppTheme.bodyFont(size: 13))
                            .foregroundStyle(AppTheme.textSecondary)
                        Text("ago")
                            .font(AppTheme.bodyFont(size: 13))
                            .foregroundStyle(AppTheme.textSecondary)
                    } else {
                        Text("Never")
                            .font(AppTheme.bodyFont(size: 13))
                            .foregroundStyle(AppTheme.textSecondary)
                    }
                }

                HStack {
                    Label("Duplicate Groups Found", systemImage: "doc.on.doc")
                        .foregroundStyle(AppTheme.textPrimary)
                    Spacer()
                    Text("\(service.duplicateGroups.count)")
                        .font(AppTheme.monoFont(size: 14))
                        .foregroundStyle(
                            service.duplicateGroups.isEmpty ? AppTheme.success : AppTheme.warning
                        )
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(
                            (service.duplicateGroups.isEmpty ? AppTheme.success : AppTheme.warning)
                                .opacity(0.15),
                            in: Capsule()
                        )
                }

                Button {
                    Task { await service.runScan(songs: library.allSongs) }
                } label: {
                    HStack {
                        Label("Scan Now", systemImage: "arrow.clockwise")
                            .foregroundStyle(AppTheme.dynamicAccent)
                        Spacer()
                        if service.isScanning {
                            ProgressView()
                                .tint(AppTheme.dynamicAccent)
                        }
                    }
                }
                .disabled(service.isScanning)

            } header: {
                sectionHeader("Status")
            } footer: {
                Text("Finds tracks that appear more than once in your library — either downloaded from the same source more than once, or matching by title and artist (e.g. once from Apple Music and once from a download).")
                    .font(AppTheme.bodyFont(size: 12))
                    .foregroundStyle(AppTheme.textSecondary)
            }
            .listRowBackground(AppTheme.surface)

            // Delete all duplicates
            if !service.allDuplicatesToRemove.isEmpty {
                Section {
                    Button(role: .destructive) {
                        showDeleteAllConfirm = true
                    } label: {
                        Label(
                            "Delete All \(service.allDuplicatesToRemove.count) Duplicate\(service.allDuplicatesToRemove.count == 1 ? "" : "s")",
                            systemImage: "trash"
                        )
                        .foregroundStyle(AppTheme.error)
                    }
                } header: {
                    sectionHeader("Actions")
                } footer: {
                    Text("Keeps the longest copy in each group and deletes the rest. Apple Music copies are never deleted.")
                        .font(AppTheme.bodyFont(size: 12))
                        .foregroundStyle(AppTheme.textSecondary)
                }
                .listRowBackground(AppTheme.surface)
            }

            // Duplicate groups
            if !service.duplicateGroups.isEmpty {
                ForEach(service.duplicateGroups) { group in
                    Section {
                        ForEach(group.songs) { song in
                            duplicateRow(song: song)
                        }
                    } header: {
                        sectionHeader("\(group.songs.count) Copies — \(group.reason.label)")
                    } footer: {
                        Text("Total playtime: \(formattedDuration(group.totalDuration)) across \(group.songs.count) copies. Longer individual copies are usually more complete — check the duration shown next to each copy before deleting.")
                            .font(AppTheme.bodyFont(size: 12))
                            .foregroundStyle(AppTheme.textSecondary)
                    }
                    .listRowBackground(AppTheme.surface)
                }
            } else if !service.isScanning && service.lastScanDate != nil {
                Section {
                    VStack(spacing: 12) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 44))
                            .foregroundStyle(AppTheme.success)
                        Text("No duplicates found")
                            .font(AppTheme.headlineFont(size: 16))
                            .foregroundStyle(AppTheme.textPrimary)
                        Text("Every track in your library appears to be unique.")
                            .font(AppTheme.bodyFont(size: 14))
                            .foregroundStyle(AppTheme.textSecondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 16)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
                    .listRowBackground(Color.clear)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(GalleryBackgroundView().ignoresSafeArea())
        .navigationTitle("Duplicate Finder")
        .navigationBarTitleDisplayMode(.large)
        .toolbarBackground(.hidden, for: .navigationBar)
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
                    service.removeSongFromGroups(songID: pending.songID)
                    pendingDeletion = nil
                }
                Button("Cancel", role: .cancel) { pendingDeletion = nil }
            }
        } message: {
            Text("This permanently deletes the downloaded file from your device. This action cannot be undone.")
        }
        .confirmationDialog(
            "Delete All Duplicates?",
            isPresented: $showDeleteAllConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete \(service.allDuplicatesToRemove.count) File\(service.allDuplicatesToRemove.count == 1 ? "" : "s")", role: .destructive) {
                for song in service.allDuplicatesToRemove {
                    library.removeImportedSong(id: song.id)
                    service.removeSongFromGroups(songID: song.id)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Keeps the longest copy in each group and permanently deletes \(service.allDuplicatesToRemove.count) other \(service.allDuplicatesToRemove.count == 1 ? "copy" : "copies"). This action cannot be undone.")
        }
    }

    // MARK: - Duplicate Row

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

    // MARK: - Helpers

    private func sectionHeader(_ text: String) -> some View {
        Text(text.uppercased())
            .font(AppTheme.bodyFont(size: 11))
            .foregroundStyle(AppTheme.textSecondary)
            .kerning(0.8)
    }

    /// Formats a total duration in seconds as "H:MM:SS" (or "M:SS" under an hour).
    private func formattedDuration(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite, seconds > 0 else { return "0:00" }
        let total = Int(seconds.rounded())
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 {
            return "\(h):\(String(format: "%02d", m)):\(String(format: "%02d", s))"
        }
        return "\(m):\(String(format: "%02d", s))"
    }
}
