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
