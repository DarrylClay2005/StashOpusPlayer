import SwiftUI

/// Shared Home/Now Playing shelf for contextual, playable station ideas.
/// Keeping the shelf independent of either screen avoids two subtly different
/// recommendation implementations and makes empty/error states unobtrusive.
struct StationSuggestionsSection: View {
    @EnvironmentObject private var account: AccountService
    @EnvironmentObject private var streaming: StreamingService
    @EnvironmentObject private var player: AudioPlayerManager

    let seed: StationSeed?

    init(seed: StationSeed? = nil, accent: Color = AppTheme.dynamicAccent) {
        self.seed = seed
        self.accent = accent
    }
    var accent: Color = AppTheme.dynamicAccent

    @State private var suggestions: [StationSuggestion] = []
    @State private var isLoading = false
    @State private var loadingStationID: String?

    private var seedKey: String {
        guard let seed else { return "home" }
        return [
            seed.title, seed.artist, seed.album, seed.genre,
            seed.bpm.map { String($0) }, seed.sourceTrackID, seed.localHour.map { String($0) }
        ]
        .compactMap { $0 }
        .joined(separator: "|")
    }

    var body: some View {
        Group {
            if isLoading || !suggestions.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    StationSectionHeader(title: "Suggestions", icon: "sparkles", accent: accent)
                        .padding(.horizontal, 16)

                    if isLoading && suggestions.isEmpty {
                        HStack {
                            ProgressView()
                            Text("Finding a station for you…")
                                .font(.caption)
                                .foregroundStyle(AppTheme.textSecondary)
                        }
                        .padding(.horizontal, 16)
                    } else {
                        ScrollView(.horizontal, showsIndicators: false) {
                            LazyHStack(spacing: 12) {
                                ForEach(suggestions) { suggestion in
                                    StationSuggestionCard(
                                        suggestion: suggestion,
                                        accent: accent,
                                        isLoading: loadingStationID == suggestion.id,
                                        onStart: { start(suggestion) }
                                    )
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 4)
                        }
                    }
                }
            }
        }
        .task(id: "\(seedKey)|\(account.isLoggedIn)") {
            await load()
        }
    }

    private func load() async {
        guard account.isLoggedIn else {
            suggestions = []
            isLoading = false
            return
        }
        isLoading = true
        let result = await account.fetchStationSuggestions(seed: seed)
        guard !Task.isCancelled else {
            isLoading = false
            return
        }
        suggestions = result
        isLoading = false
    }

    private func start(_ suggestion: StationSuggestion) {
        guard loadingStationID == nil, !suggestion.tracks.isEmpty else { return }
        loadingStationID = suggestion.id
        Task {
            defer { loadingStationID = nil }
            var songs: [Song] = []
            for track in suggestion.tracks {
                guard let url = try? await streaming.streamURL(for: track) else { continue }
                songs.append(streaming.toSong(track: track, streamURL: url))
            }
            guard let first = songs.first else { return }
            player.play(song: first, in: songs)
        }
    }
}

private struct StationSectionHeader: View {
    let title: String
    let icon: String
    let accent: Color

    var body: some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(accent)
                .frame(width: 4, height: 22)
            Image(systemName: icon)
                .foregroundStyle(accent)
            Text(title)
                .foregroundStyle(AppTheme.textPrimary)
            Spacer()
        }
        .font(.title3.weight(.bold))
    }
}

private struct StationSuggestionCard: View {
    let suggestion: StationSuggestion
    let accent: Color
    let isLoading: Bool
    let onStart: () -> Void

    var body: some View {
        Button(action: onStart) {
            VStack(alignment: .leading, spacing: 9) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(accent.opacity(0.16))
                    Image(systemName: suggestion.icon)
                        .font(.title2)
                        .foregroundStyle(accent)
                    if isLoading {
                        ProgressView()
                            .tint(.white)
                    }
                }
                .frame(width: 152, height: 108)

                Text(suggestion.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.textPrimary)
                    .lineLimit(1)
                Text(suggestion.subtitle ?? "\(suggestion.tracks.count) tracks ready to play")
                    .font(.caption2)
                    .foregroundStyle(AppTheme.textSecondary)
                    .lineLimit(2)
            }
            .frame(width: 152, alignment: .leading)
            .padding(10)
            .adaptiveGlass(
                tint: accent.opacity(0.08),
                in: RoundedRectangle(cornerRadius: 16, style: .continuous),
                fallback: AppTheme.surface
            )
        }
        .buttonStyle(PressableButtonStyle())
        .disabled(isLoading)
        .accessibilityLabel("Start \(suggestion.title)")
    }
}
