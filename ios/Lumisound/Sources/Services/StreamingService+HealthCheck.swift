import Foundation
import UIKit

extension StreamingService {

    // MARK: - Health Check

    func checkHealth() async -> Bool {
        guard isConfigured, let request = makeRequest("/health") else { return false }
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            if let httpResponse = response as? HTTPURLResponse {
                return (200..<300).contains(httpResponse.statusCode)
            }
            return false
        } catch {
            return false
        }
    }
}
