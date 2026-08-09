import Foundation

// MARK: - PodcastAutoDownloadService
//
// Opt-in (off by default) periodic pass that downloads new episodes from
// subscribed podcasts automatically, so a show is ready offline without
// having to open the app and tap download per-episode. Entirely client-
// side — reuses AccountService's existing podcast endpoints and
// PodcastDownloadManager, no new server surface.
@MainActor
enum PodcastAutoDownloadService {
    static let enabledKey = "podcastAutoDownload.enabled"
    private static let lastRunKey = "podcastAutoDownload.lastRun"

    /// Checked more often than this app's other periodic passes (which are
    /// daily) since episode freshness actually matters here — a new episode
    /// sitting unchecked for 24h defeats "ready to listen when I open the
    /// app" for shows that publish daily.
    private static let interval: TimeInterval = 6 * 60 * 60

    /// Only episodes published within this window count as "new" — without
    /// it, enabling auto-download on a long-subscribed feed with years of
    /// back-catalog would try to download the whole thing at once.
    private static let newEpisodeWindow: TimeInterval = 48 * 60 * 60

    /// Caps how many downloads one feed can start in a single pass, for the
    /// same reason — a feed that dumps a whole season at once shouldn't
    /// silently consume a large chunk of storage/data in one go.
    private static let maxDownloadsPerFeedPerPass = 3

    static var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: enabledKey) }
        set { UserDefaults.standard.set(newValue, forKey: enabledKey) }
    }

    static func runIfNeeded() async {
        guard isEnabled else { return }
        let lastRun = UserDefaults.standard.double(forKey: lastRunKey)
        guard Date().timeIntervalSince1970 - lastRun >= interval else { return }
        guard let account = AccountService.shared, account.isLoggedIn else { return }

        let subscriptions = await account.fetchPodcastSubscriptions()
        let cutoff = Date().addingTimeInterval(-newEpisodeWindow)
        let formatter = ISO8601DateFormatter()
        let downloads = PodcastDownloadManager.shared

        for subscription in subscriptions {
            let episodes = await account.fetchPodcastEpisodes(feedURL: subscription.feedURL)
            var started = 0
            for episode in episodes {
                guard started < maxDownloadsPerFeedPerPass else { break }
                guard !downloads.isDownloaded(episode.guid), !downloads.isDownloading(episode.guid) else { continue }
                guard let publishedRaw = episode.publishedAt,
                      let publishedDate = formatter.date(from: publishedRaw),
                      publishedDate >= cutoff
                else { continue }

                downloads.download(episode: episode)
                started += 1
            }
            if started > 0 {
                appLog("PodcastAutoDownloadService: started \(started) download(s) for \"\(subscription.title ?? subscription.feedURL)\"", category: "network")
            }
        }

        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: lastRunKey)
    }
}
