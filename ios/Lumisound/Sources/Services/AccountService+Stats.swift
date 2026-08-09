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
