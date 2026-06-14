import SwiftUI

// MARK: - AchievementsView
//
// Shows listening streaks and badge unlocks from GET /user/achievements.
// Badges are derived server-side from play history — nothing to configure.

struct AchievementsView: View {
    @EnvironmentObject private var account: AccountService

    private let columns = [GridItem(.adaptive(minimum: 100), spacing: 12)]

    var body: some View {
        List {
            Section {
                if let data = account.achievements {
                    LabeledContent("Current Streak") {
                        Text(streakLabel(data.currentStreakDays))
                            .font(AppTheme.monoFont(size: 14))
                            .foregroundStyle(AppTheme.textSecondary)
                    }
                    .foregroundStyle(AppTheme.textPrimary)

                    LabeledContent("Longest Streak") {
                        Text(streakLabel(data.longestStreakDays))
                            .font(AppTheme.monoFont(size: 14))
                            .foregroundStyle(AppTheme.textSecondary)
                    }
                    .foregroundStyle(AppTheme.textPrimary)

                    LabeledContent("Total Plays") {
                        Text("\(data.totalPlays)")
                            .font(AppTheme.monoFont(size: 14))
                            .foregroundStyle(AppTheme.textSecondary)
                    }
                    .foregroundStyle(AppTheme.textPrimary)

                    LabeledContent("Listening Time") {
                        Text(formattedListenTime(data.totalListenSeconds))
                            .font(AppTheme.monoFont(size: 14))
                            .foregroundStyle(AppTheme.textSecondary)
                    }
                    .foregroundStyle(AppTheme.textPrimary)
                } else {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                }
            } header: {
                sectionHeader("Streaks")
            }
            .listRowBackground(AppTheme.surface)

            if let data = account.achievements {
                Section {
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(Self.allBadges, id: \.id) { badge in
                            badgeCell(badge, unlocked: data.badges.contains(badge.id))
                        }
                    }
                    .padding(.vertical, 8)
                } header: {
                    sectionHeader("Badges")
                } footer: {
                    Text("\(data.badges.count) of \(Self.allBadges.count) unlocked")
                        .font(AppTheme.bodyFont(size: 12))
                        .foregroundStyle(AppTheme.textSecondary)
                }
                .listRowBackground(AppTheme.surface)
            }
        }
        .scrollContentBackground(.hidden)
        .background(GalleryBackgroundView().ignoresSafeArea())
        .navigationTitle("Achievements")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await account.fetchAchievements()
            checkForNewBadges()
        }
        .refreshable {
            await account.fetchAchievements()
            checkForNewBadges()
        }
    }

    // MARK: - New Badge Detection

    /// Persists earned badge ids to `UserDefaults["earnedBadges"]` (a JSON-encoded
    /// `Set<String>`) and fires a celebratory toast for any badge that's newly
    /// unlocked since the last check. Other features (e.g. settings sync) may
    /// also read/write this same key, so we merge rather than overwrite.
    private func checkForNewBadges() {
        guard let data = account.achievements else { return }
        let currentBadges = Set(data.badges)

        let defaults = UserDefaults.standard
        var earned: Set<String> = []
        if let stored = defaults.data(forKey: "earnedBadges"),
           let decoded = try? JSONDecoder().decode(Set<String>.self, from: stored) {
            earned = decoded
        }

        let newlyUnlocked = currentBadges.subtracting(earned)
        guard !newlyUnlocked.isEmpty else { return }

        let merged = earned.union(currentBadges)
        if let encoded = try? JSONEncoder().encode(merged) {
            defaults.set(encoded, forKey: "earnedBadges")
        }

        // Only toast for badges we recognize (skip silently for any future
        // server-side badge ids this build doesn't know how to display).
        for badge in Self.allBadges where newlyUnlocked.contains(badge.id) {
            ToastCenter.shared.show(
                "Achievement unlocked: \(badge.title)!",
                category: .success,
                icon: badge.icon
            )
        }
    }

    private func sectionHeader(_ text: String) -> some View {
        Text(text.uppercased())
            .font(AppTheme.bodyFont(size: 11))
            .foregroundStyle(AppTheme.textSecondary)
            .kerning(0.8)
    }

    private func streakLabel(_ days: Int) -> String {
        days == 1 ? "1 day" : "\(days) days"
    }

    private func formattedListenTime(_ seconds: Int) -> String {
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        if hours > 0 { return "\(hours)h \(minutes)m" }
        return "\(minutes)m"
    }

    @ViewBuilder
    private func badgeCell(_ badge: Badge, unlocked: Bool) -> some View {
        VStack(spacing: 6) {
            Image(systemName: badge.icon)
                .font(.system(size: 24))
                .foregroundStyle(unlocked ? AppTheme.dynamicAccent : AppTheme.textSecondary.opacity(0.4))
            Text(badge.title)
                .font(AppTheme.bodyFont(size: 11))
                .multilineTextAlignment(.center)
                .foregroundStyle(unlocked ? AppTheme.textPrimary : AppTheme.textSecondary.opacity(0.5))
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(unlocked ? AppTheme.dynamicAccent.opacity(0.12) : AppTheme.surface.opacity(0.5))
        )
        .opacity(unlocked ? 1 : 0.6)
    }

    private struct Badge {
        let id: String
        let title: String
        let icon: String
    }

    private static let allBadges: [Badge] = [
        Badge(id: "plays_10", title: "10 Plays", icon: "play.circle"),
        Badge(id: "plays_50", title: "50 Plays", icon: "play.circle.fill"),
        Badge(id: "plays_100", title: "100 Plays", icon: "repeat.circle"),
        Badge(id: "plays_500", title: "500 Plays", icon: "repeat.circle.fill"),
        Badge(id: "plays_1000", title: "1000 Plays", icon: "star.circle.fill"),
        Badge(id: "hours_1", title: "1 Hour Listened", icon: "clock"),
        Badge(id: "hours_10", title: "10 Hours Listened", icon: "clock.fill"),
        Badge(id: "hours_24", title: "24 Hours Listened", icon: "timer"),
        Badge(id: "hours_100", title: "100 Hours Listened", icon: "hourglass"),
        Badge(id: "streak_3", title: "3-Day Streak", icon: "flame"),
        Badge(id: "streak_7", title: "Week Streak", icon: "flame.fill"),
        Badge(id: "streak_30", title: "Month Streak", icon: "calendar"),
        Badge(id: "streak_100", title: "100-Day Streak", icon: "calendar.badge.clock"),
        Badge(id: "night_owl", title: "Night Owl", icon: "moon.stars.fill"),
        Badge(id: "early_bird", title: "Early Bird", icon: "sunrise.fill"),
        Badge(id: "marathon", title: "Marathon", icon: "figure.run.circle.fill"),
        Badge(id: "crate_digger", title: "Crate Digger", icon: "shippingbox.fill"),
        Badge(id: "globe_trotter", title: "Globe Trotter", icon: "globe"),
        Badge(id: "completionist", title: "Completionist", icon: "checkmark.seal.fill"),
        Badge(id: "shuffle_master", title: "Shuffle Master", icon: "shuffle"),
    ]
}
