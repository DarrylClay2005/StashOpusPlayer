import BackgroundTasks
import Foundation

/// Periodic background check for new uploads on subscribed channels and new
/// tracks on auto-download playlists, via `BGTaskScheduler` — the standard
/// iOS mechanism for this, replacing what Settings help text already
/// (inaccurately) claimed happened automatically: previously, subscriptions
/// only checked when the user tapped "Check Now", and tracked playlists only
/// checked opportunistically on launch.
///
/// IMPORTANT CAVEAT: iOS — not this code — decides if/when a submitted
/// request actually runs. It won't fire before `earliestBeginDate`, and past
/// that the OS schedules it based on the device's usage patterns, battery
/// level, and network state; there is no guaranteed cadence, and it may not
/// run for long stretches if the app isn't opened often. This can't be
/// verified from a dev machine with no physical device — if a user reports
/// subscriptions never update in the background, that's the first thing to
/// suspect (and "Check Now" always still works as a manual fallback).
enum BackgroundRefreshService {
    static let taskIdentifier = "com.lumisound.ios.refresh"

    /// Registers the task handler. MUST be called before the app finishes
    /// launching — from `LumisoundApp.init()`, not a View's `.task`/`.onAppear`
    /// (BGTaskScheduler requires registration before the app is fully active).
    static func register() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: taskIdentifier, using: nil) { task in
            guard let refreshTask = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            handle(task: refreshTask)
        }
    }

    /// Requests the next background run. Call once after launch and again
    /// after each run completes — a submitted request is consumed when it
    /// fires (or replaced by a newer `submit()` for the same identifier).
    static func scheduleNext() {
        let request = BGAppRefreshTaskRequest(identifier: taskIdentifier)
        // Requested as soon as 5 minutes out, matching TrackedPlaylistStore's
        // own 5-minute auto-download throttle — but this is only the
        // EARLIEST iOS is allowed to run it, not a promise it will. In
        // practice BGAppRefreshTask is scheduled at the OS's discretion
        // based on usage patterns/battery/network state and routinely runs
        // far less often than requested (see this file's top-level doc
        // comment) — a 5-minute request does not produce 5-minute cadence,
        // it just removes the 4-hour floor that used to be here.
        request.earliestBeginDate = Date(timeIntervalSinceNow: 5 * 60)
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            appWarn("BackgroundRefreshService: submit failed: \(error.localizedDescription)", category: "background")
        }
    }

    private static func handle(task: BGAppRefreshTask) {
        // Schedule the NEXT run before doing any work — if this run fails or
        // is cut short by the OS, the periodic chain continues regardless.
        scheduleNext()

        let work = Task {
            await runChecks()
            task.setTaskCompleted(success: true)
        }
        task.expirationHandler = {
            work.cancel()
        }
    }

    @MainActor
    private static func runChecks() async {
        appLog("BackgroundRefreshService: running checks", category: "background")
        await AccountService.shared?.checkAllSubscriptions()

        guard let library = LibraryManager.shared, let streaming = StreamingService.shared else { return }

        // Pick up any downloads that finished server-side while the app
        // wasn't around to fetch them (see StreamingService+PendingDownloads)
        // — done first and cheaply (a single GET when there's nothing
        // pending), so it isn't starved by runAutoDownloads below if this
        // task's tight execution budget runs out first.
        await streaming.reconcilePendingDownloads()

        await TrackedPlaylistStore.shared.runAutoDownloads(streaming: streaming, library: library)
    }
}
