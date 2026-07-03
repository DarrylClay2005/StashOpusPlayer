import SwiftUI

/// Harmonic-mixing recommendations for a cloud-backed track — wires up the
/// bridge's `/user/music/recommendations` (Camelot-key + tempo-ratio
/// matching over the user's already-analyzed uploads), which previously had
/// no client caller at all.
struct RecommendationsSheet: View {
    let seed: UserMusicMetadataTrack
    let token: String?

    @EnvironmentObject private var streaming: StreamingService
    @Environment(\.dismiss) private var dismiss

    @State private var isLoading = true
    @State private var tracks: [RecommendedTrack] = []
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView("Finding compatible tracks…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let errorMessage {
                    VStack(spacing: 10) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 32))
                            .foregroundStyle(AppTheme.warning)
                        Text(errorMessage)
                            .font(AppTheme.bodyFont(size: 14))
                            .foregroundStyle(AppTheme.textSecondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if tracks.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "wand.and.stars")
                            .font(.system(size: 32))
                            .foregroundStyle(AppTheme.textSecondary)
                        Text("No compatible tracks found in your cloud library yet.")
                            .font(AppTheme.bodyFont(size: 14))
                            .foregroundStyle(AppTheme.textSecondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(tracks) { track in
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(track.title ?? track.filename)
                                    .font(AppTheme.bodyFont(size: 14).weight(.medium))
                                    .foregroundStyle(AppTheme.textPrimary)
                                    .lineLimit(1)
                                HStack(spacing: 6) {
                                    if let artist = track.artist, !artist.isEmpty {
                                        Text(artist)
                                            .font(AppTheme.bodyFont(size: 12))
                                            .foregroundStyle(AppTheme.textSecondary)
                                            .lineLimit(1)
                                    }
                                    Text(track.tempoKeyText)
                                        .font(AppTheme.monoFont(size: 11))
                                        .foregroundStyle(AppTheme.textSecondary)
                                }
                            }
                            Spacer()
                            if track.keyCompatible {
                                Label("Key", systemImage: "music.note")
                                    .labelStyle(.iconOnly)
                                    .font(.system(size: 12))
                                    .foregroundStyle(AppTheme.success)
                            }
                        }
                        .listRowBackground(AppTheme.surface)
                    }
                    .scrollContentBackground(.hidden)
                }
            }
            .background(GalleryBackgroundView().ignoresSafeArea())
            .navigationTitle("Similar to \(seed.title ?? seed.filename)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .task {
                await load()
            }
        }
    }

    private func load() async {
        guard let token else {
            errorMessage = "Sign in to see recommendations."
            isLoading = false
            return
        }
        do {
            let response = try await streaming.fetchRecommendations(seedID: seed.id, token: token)
            tracks = response.tracks
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}
