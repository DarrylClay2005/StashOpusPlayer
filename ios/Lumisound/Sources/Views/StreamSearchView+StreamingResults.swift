import SwiftUI
import UniformTypeIdentifiers

extension StreamSearchView {

    // MARK: — Streaming results (YouTube / SoundCloud)

    var streamResultsBody: some View {
        Group {
            if streaming.isSearching || streaming.isResolvingPlaylist {
                Spacer()
                ProgressView(streaming.isResolvingPlaylist ? "Loading playlist…" : "Searching…")
                    .tint(AppTheme.dynamicAccent)
                    .foregroundStyle(AppTheme.textSecondary)
                Spacer()
            } else if searchText.isEmpty {
                trendingSearchesBody
            } else if streaming.searchResults.isEmpty {
                VStack(spacing: 0) {
                    if !suggestions.isEmpty {
                        suggestionsBody
                    }
                    Spacer()
                    Text("No results for \"\(searchText)\"")
                        .font(AppTheme.bodyFont(size: 15))
                        .foregroundStyle(AppTheme.textSecondary)
                    Spacer()
                }
            } else {
                VStack(spacing: 0) {
                    // Playlist banner — only shown after a successful playlist resolve
                    if streaming.isPlaylistResult && !streaming.searchResults.isEmpty {
                        VStack(spacing: 8) {
                            HStack(spacing: 10) {
                                Image(systemName: "music.note.list")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundStyle(AppTheme.dynamicAccent)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text("Playlist")
                                        .font(AppTheme.bodyFont(size: 11).weight(.semibold))
                                        .foregroundStyle(AppTheme.textSecondary)
                                        .kerning(0.6)
                                    Text("\(streaming.searchResults.count) tracks")
                                        .font(AppTheme.bodyFont(size: 15).weight(.semibold))
                                        .foregroundStyle(AppTheme.textPrimary)
                                }
                                Spacer()
                                if isDownloadingAll {
                                    HStack(spacing: 6) {
                                        ProgressView()
                                            .tint(AppTheme.dynamicAccent)
                                            .scaleEffect(0.8)
                                        Text("\(downloadAllDone)/\(downloadAllTotal)")
                                            .font(AppTheme.monoFont(size: 13))
                                            .foregroundStyle(AppTheme.textSecondary)
                                    }
                                } else if !failedTrackIDs.isEmpty {
                                    // Only the tracks that failed last time are retried — no
                                    // full search/resolve refresh, unlike the generic error
                                    // banner's "Retry" which re-resolves the whole playlist.
                                    Button {
                                        handleRetryFailedDownloads()
                                    } label: {
                                        Label("Retry \(failedTrackIDs.count)", systemImage: "arrow.clockwise")
                                            .font(AppTheme.bodyFont(size: 13).weight(.semibold))
                                            .foregroundStyle(AppTheme.warning)
                                            .padding(.horizontal, 12)
                                            .padding(.vertical, 7)
                                            .adaptiveGlass(in: Capsule(), fallback: AppTheme.warning.opacity(0.15))
                                    }
                                    .buttonStyle(.plain)
                                } else {
                                    Button {
                                        handleDownloadAll()
                                    } label: {
                                        Label("Download All", systemImage: "arrow.down.circle.fill")
                                            .font(AppTheme.bodyFont(size: 13).weight(.semibold))
                                            .foregroundStyle(.white)
                                            .padding(.horizontal, 12)
                                            .padding(.vertical, 7)
                                            .adaptiveGlass(tint: AppTheme.dynamicAccent, in: Capsule(), fallback: AppTheme.dynamicAccent)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }

                            // Determinate progress bar while a "Download All" run is active.
                            if isDownloadingAll && downloadAllTotal > 0 {
                                ProgressView(value: Double(downloadAllDone), total: Double(downloadAllTotal))
                                    .tint(AppTheme.dynamicAccent)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(AppTheme.surface)
                    }

                    List {
                        // Group results into per-source sections (YouTube / SoundCloud)
                        // so the user can clearly tell which platform each result came
                        // from. Most single-source searches will only populate one
                        // section, but playlist resolves can mix sources.
                        ForEach(groupedResults, id: \.source) { group in
                            Section {
                                ForEach(Array(group.tracks.enumerated()), id: \.element.id) { localIndex, track in
                                    // Cap the stagger index: it only drives the fade-in delay, and
                                    // the old `searchResults.firstIndex` lookup here was O(n) per
                                    // row → O(n²) over a big playlist (a main-thread hang).
                                    let globalIndex = min(localIndex, 12)
                                    StreamTrackRow(
                                        track: track,
                                        isLoading: loadingTrackID == track.id,
                                        isDownloading: downloadingTrackIDs.contains(track.id),
                                        isDownloaded: downloadedTrackIDs.contains(track.id),
                                        onPlay: { handlePlay(track: track) },
                                        onAddToQueue: { handleAddToQueue(track: track) },
                                        onDownload: { handleDownload(track: track) }
                                    )
                                    .listRowBackground(AppTheme.surface)
                                    .listRowSeparatorTint(AppTheme.background)
                                    // Staggered fade-in when results first appear
                                    .modifier(StaggeredFadeInModifier(index: globalIndex, token: resultsAnimationToken))
                                    .contextMenu {
                                        Button {
                                            handlePlayNext(track: track)
                                        } label: {
                                            Label("Play Next", systemImage: "text.line.first.and.arrowtriangle.forward")
                                        }
                                        Button {
                                            handleAddToQueue(track: track)
                                        } label: {
                                            Label("Add to Queue", systemImage: "text.line.last.and.arrowtriangle.forward")
                                        }
                                        Button {
                                            handleDownload(track: track)
                                        } label: {
                                            Label("Download", systemImage: "arrow.down.circle")
                                        }
                                        if !track.youtubeURL.isEmpty, let linkURL = URL(string: track.youtubeURL) {
                                            Divider()
                                            Button {
                                                UIPasteboard.general.string = track.youtubeURL
                                            } label: {
                                                Label("Copy Link", systemImage: "link")
                                            }
                                            ShareLink(item: linkURL) {
                                                Label("Share", systemImage: "square.and.arrow.up")
                                            }
                                        }
                                    }
                                }
                            } header: {
                                Text(sourceLabel(group.source))
                                    .font(AppTheme.bodyFont(size: 12).weight(.semibold))
                                    .foregroundStyle(AppTheme.textSecondary)
                                    .kerning(0.8)
                            }
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }
            }
        }
    }
}
