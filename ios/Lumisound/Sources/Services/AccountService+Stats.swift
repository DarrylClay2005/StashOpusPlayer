import Foundation
import SwiftUI
import UIKit

extension AccountService {

    // MARK: - Stats

    /// Fetches lifetime listening stats (total plays/time, top artists/tracks).
    func fetchStats() async {
        guard isLoggedIn else { return }
        do {
            let data = try await makeRequest("/user/stats")
            stats = try JSONDecoder().decode(AccountStats.self, from: data)
        } catch let err as AccountError {
            errorMessage = err.message
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Fetches the annual "Wrapped"-style recap for `year` (defaults to the
    /// current year). Powers `YearInReviewView`'s shareable card.
    func fetchYearInReview(year: Int? = nil) async {
        guard isLoggedIn else { return }
        do {
            let path = year.map { "/user/stats/year-in-review?year=\($0)" } ?? "/user/stats/year-in-review"
            let data = try await makeRequest(path)
            yearInReview = try JSONDecoder().decode(YearInReview.self, from: data)
        } catch let err as AccountError {
            errorMessage = err.message
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Fetches the monthly "Wrapped"-style recap for `year`/`month` (both
    /// default to the current UTC calendar month). Powers `RewindView`'s
    /// "This Month" mode.
    func fetchMonthInReview(year: Int? = nil, month: Int? = nil) async {
        guard isLoggedIn else { return }
        do {
            var query: [String] = []
            if let year { query.append("year=\(year)") }
            if let month { query.append("month=\(month)") }
            let path = query.isEmpty ? "/user/stats/month-in-review" : "/user/stats/month-in-review?\(query.joined(separator: "&"))"
            let data = try await makeRequest(path)
            monthInReview = try JSONDecoder().decode(MonthInReview.self, from: data)
        } catch let err as AccountError {
            errorMessage = err.message
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Fetches per-day play counts/listen time for the last 7 days —
    /// powers `ListeningGoalService`'s weekly progress tracking. Same
    /// response shape as `fetchListeningHeatmap`, reused via `HeatmapDay`
    /// rather than a duplicate model, just hitting the shorter-range
    /// /user/stats/weekly endpoint instead of /user/stats/heatmap.
    func fetchWeeklyStats() async -> [HeatmapDay] {
        guard isLoggedIn else { return [] }
        do {
            let data = try await makeRequest("/user/stats/weekly")
            return try JSONDecoder().decode([HeatmapDay].self, from: data)
        } catch {
            appWarn("fetchWeeklyStats: \(error.localizedDescription)", category: "network")
            return []
        }
    }

    /// Fetches per-day play counts/listen time for the last `days` days
    /// (default a year) — powers `ListeningHeatmapView`'s calendar heatmap.
    /// Empty on failure or if there's no history yet.
    func fetchListeningHeatmap(days: Int = 365) async -> [HeatmapDay] {
        guard isLoggedIn else { return [] }
        do {
            let data = try await makeRequest("/user/stats/heatmap?days=\(days)")
            return try JSONDecoder().decode([HeatmapDay].self, from: data)
        } catch {
            appWarn("fetchListeningHeatmap: \(error.localizedDescription)", category: "network")
            return []
        }
    }

    /// Fetches listening streaks and badge unlocks (derived server-side from play history).
    func fetchAchievements() async {
        guard isLoggedIn else { return }
        do {
            let data = try await makeRequest("/user/achievements")
            achievements = try JSONDecoder().decode(AchievementsData.self, from: data)
        } catch let err as AccountError {
            errorMessage = err.message
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
