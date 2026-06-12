import SwiftUI

// MARK: - BackupHistoryView
//
// Shows the automatic server-side sync backups for this account (taken
// before every push and before every restore — see `ios_user_backups` and
// GET/POST /user/backups... on the bridge). Lets the user roll back to a
// previous snapshot of their favorites/playlists/settings if a bad sync
// ever overwrites their data.

struct BackupHistoryView: View {
    @EnvironmentObject private var account: AccountService
    @EnvironmentObject private var library: LibraryManager
    @EnvironmentObject private var player: AudioPlayerManager

    @State private var isLoading = false
    @State private var pendingRestore: SyncBackup?

    var body: some View {
        List {
            if isLoading && account.backups.isEmpty {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
                .listRowBackground(AppTheme.surface)
            } else if account.backups.isEmpty {
                Text("No backups yet. A snapshot is taken automatically every time your data syncs to the server.")
                    .font(AppTheme.bodyFont(size: 13))
                    .foregroundStyle(AppTheme.textSecondary)
                    .listRowBackground(AppTheme.surface)
            } else {
                Section {
                    ForEach(account.backups) { backup in
                        Button {
                            pendingRestore = backup
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 3) {
                                    if let date = backup.date {
                                        Text(date, style: .relative)
                                            .font(AppTheme.bodyFont(size: 14))
                                            .foregroundStyle(AppTheme.textPrimary)
                                    } else {
                                        Text(backup.createdAt)
                                            .font(AppTheme.bodyFont(size: 14))
                                            .foregroundStyle(AppTheme.textPrimary)
                                    }
                                    Text("\(backup.reasonDisplayName) · \(backup.favoriteCount) favorites, \(backup.playlistCount) playlists")
                                        .font(AppTheme.bodyFont(size: 12))
                                        .foregroundStyle(AppTheme.textSecondary)
                                }
                                Spacer()
                                Image(systemName: "arrow.uturn.backward.circle")
                                    .foregroundStyle(AppTheme.dynamicAccent)
                            }
                        }
                        .disabled(account.isSyncing)
                    }
                } header: {
                    Text("BACKUPS")
                        .font(AppTheme.bodyFont(size: 11))
                        .foregroundStyle(AppTheme.textSecondary)
                        .kerning(0.8)
                } footer: {
                    Text("Restoring replaces your favorites, playlists, and synced settings with this snapshot, then merges the result onto this device. The current state is backed up first, so a restore can always be undone.")
                        .font(AppTheme.bodyFont(size: 12))
                        .foregroundStyle(AppTheme.textSecondary)
                }
                .listRowBackground(AppTheme.surface)
            }
        }
        .scrollContentBackground(.hidden)
        .background(GalleryBackgroundView().ignoresSafeArea())
        .navigationTitle("Backup History")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            isLoading = true
            await account.fetchBackups()
            isLoading = false
        }
        .refreshable {
            await account.fetchBackups()
        }
        .confirmationDialog(
            "Restore this backup?",
            isPresented: Binding(
                get: { pendingRestore != nil },
                set: { if !$0 { pendingRestore = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Restore", role: .destructive) {
                guard let backup = pendingRestore else { return }
                pendingRestore = nil
                Task { await account.restoreBackup(id: backup.id, library: library, player: player) }
            }
            Button("Cancel", role: .cancel) { pendingRestore = nil }
        } message: {
            if let backup = pendingRestore, let date = backup.date {
                Text("This replaces your current favorites, playlists, and synced settings with the snapshot from \(date.formatted(.relative(presentation: .named))).")
            } else {
                Text("This replaces your current favorites, playlists, and synced settings with this snapshot.")
            }
        }
    }
}
