import Foundation
import UIKit

/// Wraps a download in a `UIBackgroundTaskIdentifier` so it can finish even if the
/// user switches apps briefly during a playlist "Download All" operation.
/// Provides ~30 seconds of extra background execution time per download.
enum BackgroundDownloadManager {
    static func run<T>(
        named name: String,
        work: () async throws -> T
    ) async throws -> T {
        var taskID: UIBackgroundTaskIdentifier = .invalid
        var expired = false

        taskID = UIApplication.shared.beginBackgroundTask(withName: name) {
            expired = true
            UIApplication.shared.endBackgroundTask(taskID)
            taskID = .invalid
        }

        defer {
            if taskID != .invalid {
                UIApplication.shared.endBackgroundTask(taskID)
            }
        }

        if expired { throw CancellationError() }
        return try await work()
    }
}
