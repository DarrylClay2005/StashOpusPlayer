import Foundation
import SwiftUI
import UIKit

extension AccountService {

    // MARK: - Discover Mix

    /// Fetches a "Discover Mix" of suggested tracks seeded from the user's
    /// most-played artists, excluding tracks already in their library/favorites.
    func fetchDiscoverMix(limit: Int = 20) async -> [StreamTrack] {
        guard isLoggedIn else { return [] }
        do {
            let data = try await makeRequest("/user/discover-mix?limit=\(limit)")
            return try JSONDecoder().decode([StreamTrack].self, from: data)
        } catch let err as AccountError {
            errorMessage = err.message
            return []
        } catch {
            errorMessage = error.localizedDescription
            return []
        }
    }
}
