import Foundation
import UIKit

/// Wraps a download in a `UIBackgroundTaskIdentifier` so it can finish even if the
/// user switches apps briefly during a playlist "Download All" operation.
/// Provides ~30 seconds of extra background execution time per download.
enum BackgroundDownloadManager {

    /// `beginBackgroundTask`'s expiration handler fires on the main thread, while
    /// `run`'s `defer` resumes on whatever executor the awaited work completes on —
    /// so both can race to read/write the task identifier and end it. This box
    /// serializes those accesses behind a lock and a one-shot `ended` flag so
    /// `endBackgroundTask` is called exactly once, however the two interleave.
    /// (Calling it twice with the same identifier is documented as a fatal misuse.)
    private final class TaskBox: @unchecked Sendable {
        private let lock = NSLock()
        private var taskID: UIBackgroundTaskIdentifier = .invalid
        private var ended = false

        func register(_ id: UIBackgroundTaskIdentifier) {
            lock.lock()
            let alreadyEnded = ended
            if !alreadyEnded { taskID = id }
            lock.unlock()
            // Expired before registration finished — end immediately rather than leak it.
            if alreadyEnded, id != .invalid {
                UIApplication.shared.endBackgroundTask(id)
            }
        }

        func endIfNeeded() {
            lock.lock()
            guard !ended else { lock.unlock(); return }
            ended = true
            let id = taskID
            taskID = .invalid
            lock.unlock()
            if id != .invalid {
                UIApplication.shared.endBackgroundTask(id)
            }
        }

        var hasExpired: Bool {
            lock.lock()
            defer { lock.unlock() }
            return ended
        }
    }

    static func run<T>(
        named name: String,
        work: () async throws -> T
    ) async throws -> T {
        let box = TaskBox()
        let id = UIApplication.shared.beginBackgroundTask(withName: name) {
            box.endIfNeeded()
        }
        box.register(id)
        defer { box.endIfNeeded() }

        if box.hasExpired { throw CancellationError() }
        return try await work()
    }
}
