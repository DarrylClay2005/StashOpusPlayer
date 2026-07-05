import SwiftUI
import UniformTypeIdentifiers

extension StreamSearchView {

    // MARK: — Trending searches & suggestions

    var trendingSearchesBody: some View {
        Group {
            if trendingQueries.isEmpty {
                Spacer()
                Text("Search YouTube or SoundCloud, or paste a playlist URL — including a Bandcamp track or album link.")
                    .font(AppTheme.bodyFont(size: 14))
                    .foregroundStyle(AppTheme.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                Spacer()
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 6) {
                            Image(systemName: "flame.fill")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(AppTheme.dynamicAccent)
                            Text("TRENDING SEARCHES")
                                .font(AppTheme.bodyFont(size: 11))
                                .foregroundStyle(AppTheme.textSecondary)
                                .kerning(0.8)
                        }
                        .padding(.horizontal, 4)
                        .padding(.top, 8)

                        ForEach(Array(trendingQueries.enumerated()), id: \.element.id) { idx, item in
                            Button {
                                searchText = item.query
                                triggerSearch()
                            } label: {
                                HStack(spacing: 12) {
                                    ZStack {
                                        Circle()
                                            .fill(AppTheme.dynamicAccent.opacity(0.15))
                                            .frame(width: 34, height: 34)
                                        Text("\(idx + 1)")
                                            .font(.system(size: 14, weight: .bold, design: .rounded))
                                            .foregroundStyle(AppTheme.dynamicAccent)
                                    }
                                    Text(item.query)
                                        .font(AppTheme.bodyFont(size: 15))
                                        .foregroundStyle(AppTheme.textPrimary)
                                        .lineLimit(1)
                                    Spacer(minLength: 8)
                                    Image(systemName: "magnifyingglass")
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(AppTheme.textSecondary)
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 11)
                                .background(
                                    AppTheme.surface,
                                    in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .stroke(.white.opacity(0.05), lineWidth: 1)
                                )
                            }
                            .buttonStyle(PressableButtonStyle())
                        }
                    }
                    .padding(.horizontal, 16)
                    // Extra clearance below the last row — MiniPlayerBar
                    // (80pt) + tab bar (~83pt) + margin, see SongsTab's
                    // identical fix.
                    .padding(.bottom, 190)
                }
                .scrollContentBackground(.hidden)
            }
        }
    }

    var suggestionsBody: some View {
        VStack(spacing: 0) {
            ForEach(suggestions) { item in
                Button {
                    searchText = item.query
                    triggerSearch()
                } label: {
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(AppTheme.textSecondary)
                            .frame(width: 20)
                        Text(item.query)
                            .font(AppTheme.bodyFont(size: 14))
                            .foregroundStyle(AppTheme.textPrimary)
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                }
                .buttonStyle(.plain)
                Divider().background(AppTheme.background)
            }
        }
        .background(AppTheme.surface)
    }
}
