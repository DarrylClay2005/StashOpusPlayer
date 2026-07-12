import SwiftUI
import UniformTypeIdentifiers

extension StreamSearchView {

    // MARK: — My Library body

    var userLibraryBody: some View {
        Group {
            if !account.isLoggedIn {
                VStack {
                    Spacer()
                    VStack(spacing: 12) {
                        Image(systemName: "person.crop.circle.badge.questionmark")
                            .font(.system(size: 44))
                            .foregroundStyle(AppTheme.textSecondary)
                        Text("Log in to access your personal library")
                            .font(AppTheme.bodyFont(size: 15))
                            .foregroundStyle(AppTheme.textSecondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                    }
                    Spacer()
                }
            } else if streaming.isLoadingUserMusic {
                VStack {
                    Spacer()
                    ProgressView("Loading your library…")
                        .tint(AppTheme.dynamicAccent)
                        .foregroundStyle(AppTheme.textSecondary)
                    Spacer()
                }
            } else {
                List {
                    if !searchText.isEmpty && !matchingLocalSongs.isEmpty {
                        Section("On This Device") {
                            ForEach(matchingLocalSongs) { song in
                                SongRow(song: song, isCurrent: player.currentSong?.id == song.id)
                                    .listRowBackground(AppTheme.surface)
                                    .listRowSeparatorTint(AppTheme.background)
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        player.play(song: song, in: matchingLocalSongs)
                                    }
                            }
                        }
                    }

                    if !searchText.isEmpty && !matchingDownloadHistory.isEmpty {
                        Section("Previously Downloaded") {
                            ForEach(matchingDownloadHistory) { item in
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(item.title)
                                            .font(AppTheme.bodyFont(size: 15))
                                            .foregroundStyle(AppTheme.textPrimary)
                                            .lineLimit(1)
                                        Text(item.artist)
                                            .font(.caption)
                                            .foregroundStyle(AppTheme.textSecondary)
                                            .lineLimit(1)
                                    }
                                    Spacer()
                                    if downloadingTrackIDs.contains(item.id) {
                                        ProgressView().tint(AppTheme.dynamicAccent)
                                    } else if downloadedTrackIDs.contains(item.id) {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(.green)
                                    } else {
                                        Button {
                                            handleDownload(track: item.asStreamTrack)
                                        } label: {
                                            Image(systemName: "arrow.down.circle")
                                                .foregroundStyle(AppTheme.dynamicAccent)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                .listRowBackground(AppTheme.surface)
                                .listRowSeparatorTint(AppTheme.background)
                            }
                        }
                    }

                    // Storage usage — the one piece of the Personal Cloud
                    // Library the server has always tracked (GET
                    // /user/storage/usage) but the app never showed, so this
                    // screen read as "a file list with no sense of what your
                    // account actually holds or how much room is left."
                    if let usage = streaming.storageUsage {
                        Section {
                            StorageUsageRow(usage: usage)
                        }
                        .listRowBackground(AppTheme.surface)
                    }

                    // Upload button header
                    Section {
                        Button {
                            showUploadPicker = true
                        } label: {
                            HStack {
                                Label("Upload Music to Server", systemImage: "icloud.and.arrow.up")
                                    .foregroundStyle(AppTheme.dynamicAccent)
                                Spacer()
                                if streaming.isUploadingUserMusic {
                                    ProgressView()
                                        .tint(AppTheme.dynamicAccent)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .disabled(streaming.isUploadingUserMusic)
                    }
                    .listRowBackground(AppTheme.surface)

                    if streaming.userMusicTracks.isEmpty {
                        Section {
                            VStack(spacing: 12) {
                                Image(systemName: "folder.badge.plus")
                                    .font(.system(size: 40))
                                    .foregroundStyle(AppTheme.textSecondary)
                                Text("Your library is empty")
                                    .font(AppTheme.headlineFont(size: 16))
                                    .foregroundStyle(AppTheme.textPrimary)
                                Text("Upload music files to your personal server folder to play them anywhere.")
                                    .font(AppTheme.bodyFont(size: 14))
                                    .foregroundStyle(AppTheme.textSecondary)
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal, 20)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 30)
                            .listRowBackground(Color.clear)
                        }
                    } else {
                        ForEach(streaming.userMusicTracks) { track in
                            UserMusicTrackRow(
                                track: track,
                                artworkURL: streaming.userMusicArtworkURL(for: track),
                                onPlay: { handleUserLibraryPlay(track: track) },
                                onInfo: { selectedInfoTrack = track },
                                onDelete: { handleUserLibraryDelete(track: track) }
                            )
                            .listRowBackground(AppTheme.surface)
                            .listRowSeparatorTint(AppTheme.background)
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
    }
}

// MARK: - StorageUsageRow

/// Compact "used of quota" summary + progress bar for the Personal Cloud
/// Library, shown at the top of the "My Library" tab.
private struct StorageUsageRow: View {
    let usage: StorageUsage

    private static let byteFormatter: ByteCountFormatter = {
        let f = ByteCountFormatter()
        f.countStyle = .file
        return f
    }()

    private var usedText: String { Self.byteFormatter.string(fromByteCount: Int64(usage.usedBytes)) }
    private var quotaText: String { Self.byteFormatter.string(fromByteCount: Int64(usage.quotaBytes)) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Storage", systemImage: "internaldrive")
                    .foregroundStyle(AppTheme.textPrimary)
                Spacer()
                Text(usage.isUnlimited ? usedText : "\(usedText) of \(quotaText)")
                    .font(.footnote)
                    .foregroundStyle(usage.quotaExceeded ? AppTheme.error : AppTheme.textSecondary)
            }

            if let fraction = usage.usedFraction {
                ProgressView(value: fraction)
                    .tint(usage.quotaExceeded ? AppTheme.error : AppTheme.dynamicAccent)
            }

            Text("\(usage.musicCount) \(usage.musicCount == 1 ? "track" : "tracks")\(usage.galleryBytes > 0 ? " · gallery backups included" : "")")
                .font(.caption)
                .foregroundStyle(AppTheme.textSecondary)

            if usage.quotaExceeded {
                Text("You're over your storage quota — delete a few tracks or ask the server admin to raise it.")
                    .font(.caption)
                    .foregroundStyle(AppTheme.error)
            }
        }
        .padding(.vertical, 4)
    }
}
