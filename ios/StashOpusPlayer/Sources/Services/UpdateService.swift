import Foundation
import UIKit

@MainActor
final class UpdateService: ObservableObject {
    static let shared = UpdateService()

    @Published private(set) var latestVersion: String? = nil
    @Published private(set) var updateAvailable: Bool = false
    @Published private(set) var isChecking: Bool = false
    @Published private(set) var releasePageURL: URL = URL(string: "https://github.com/HeavenlyXenusVR/StashOpusPlayer/releases/latest")!

    var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"
    }

    private init() {}

    func openReleasePage() {
        UIApplication.shared.open(releasePageURL)
    }

    func checkForUpdates() async {
        guard !isChecking else { return }
        isChecking = true
        defer { isChecking = false }

        let apiURL = URL(string: "https://api.github.com/repos/HeavenlyXenusVR/StashOpusPlayer/releases")!
        var request = URLRequest(url: apiURL)
        request.setValue("StashOpusPlayer-iOS", forHTTPHeaderField: "User-Agent")

        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            guard let releases = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
                return
            }

            // Look for the best iOS-specific release first (tag starts with "ios/v"),
            // falling back to any tag starting with "v".
            var bestTag: String? = nil
            var bestPageURL: URL? = nil

            for release in releases {
                guard let tagName = release["tag_name"] as? String,
                      let htmlURL = release["html_url"] as? String
                else { continue }

                let isDraft = release["draft"] as? Bool ?? false
                let isPrerelease = release["prerelease"] as? Bool ?? false
                guard !isDraft, !isPrerelease else { continue }

                if tagName.hasPrefix("ios/v") {
                    bestTag = String(tagName.dropFirst("ios/v".count))
                    bestPageURL = URL(string: htmlURL)
                    break   // ios/v prefix is preferred; stop on first match.
                }

                if tagName.hasPrefix("v"), bestTag == nil {
                    bestTag = String(tagName.dropFirst(1))
                    bestPageURL = URL(string: htmlURL)
                }
            }

            guard let versionString = bestTag else { return }

            latestVersion = versionString
            if let pageURL = bestPageURL {
                releasePageURL = pageURL
            }
            updateAvailable = isNewerVersion(versionString, than: currentVersion)
        } catch {
            // Silently fail — network errors should not crash or alert the user.
        }
    }

    // MARK: - Version Comparison

    /// Returns `true` if `candidate` is strictly newer than `current`.
    /// Compares dot-separated integer components (e.g. "1.2.3" > "1.2.0").
    private func isNewerVersion(_ candidate: String, than current: String) -> Bool {
        let candidateParts = versionComponents(candidate)
        let currentParts   = versionComponents(current)

        let maxLen = max(candidateParts.count, currentParts.count)
        for i in 0..<maxLen {
            let c = i < candidateParts.count ? candidateParts[i] : 0
            let s = i < currentParts.count   ? currentParts[i]   : 0
            if c > s { return true }
            if c < s { return false }
        }
        return false  // equal versions
    }

    private func versionComponents(_ version: String) -> [Int] {
        version.split(separator: ".").compactMap { Int($0) }
    }
}
