import Foundation

// MARK: - AppLogger

/// Thread-safe application logger. Buffers entries in memory and flushes them
/// to the bridge server every 30 seconds (or immediately on errors).
///
/// `log()` / `warn()` / `error()` are `nonisolated` and can be called from any
/// thread, actor, or Task without `await`. The actual buffer write hops to
/// MainActor asynchronously so the caller is never blocked.
@MainActor
final class AppLogger: ObservableObject {

    static let shared = AppLogger()

    // MARK: - LogEntry

    struct LogEntry: Codable {
        let level: String       // "debug", "info", "warning", "error"
        let category: String    // "audio", "library", "account", "ui", "network", "artwork", "general"
        let message: String
        let file: String
        let line: Int
        let timestamp: String   // ISO 8601
        var extra: [String: String]
        // Device/account context — lets server-side log queries be filtered or
        // grouped per device model, OS version, app build, and (when logged in)
        // per-user, so issues reported by one user's device don't get conflated
        // with another's.
        var deviceModel: String = DeviceInfo.modelIdentifier
        var osVersion: String = DeviceInfo.osVersion
        var appVersion: String = DeviceInfo.appVersion
        var userId: String? = nil
    }

    // MARK: - Private state (all @MainActor)

    private var buffer: [LogEntry] = []
    private let maxBuffer = 1_000

    /// Separate from `buffer`: holds the last `maxRecentEntries` log entries for
    /// `recentActivitySummary()`, independent of the flush-to-bridge cycle.
    /// `buffer` is drained (set to `[]`) every 30s by `flush()`, so by the time a
    /// user notices a problem, navigates to Settings → Report a Bug, and fills out
    /// the form, `buffer` is almost always empty — "include recent activity log"
    /// had nothing to attach. This buffer is never cleared by `flush()`, only
    /// trimmed to its cap, so it always reflects what actually just happened.
    private var recentEntries: [LogEntry] = []
    private let maxRecentEntries = 50
    private var flushTimer: Timer?
    private var bridgeURL: String = ""
    private var isConfigured = false

    // MARK: - Breadcrumbs (crash context)

    private static let breadcrumbsKey = "crash_breadcrumbs_v1"
    private let maxBreadcrumbs = 12
    private var breadcrumbs: [String] = []

    private init() {}

    // MARK: - Configuration

    /// Call once on app launch. Subsequent calls (e.g. from SwiftUI `.task` re-fires) are no-ops.
    func configure(bridgeURL: String) {
        guard !isConfigured else { return }
        isConfigured = true
        self.bridgeURL = bridgeURL
        reportPriorSessionBreadcrumbsIfAny()
        _append(LogEntry(level: "info", category: "app", message: "App launched",
                         file: "LumisoundApp.swift", line: 0,
                         timestamp: Date().formatted(.iso8601), extra: [:]))
        startFlushTimer()
    }

    // MARK: - Breadcrumbs (nonisolated — callable from any context)

    /// Records a short description of a significant action (scan started, song
    /// changed, tab switched...) and persists the trail to UserDefaults
    /// immediately. If the app crashes before the next graceful shutdown, the
    /// *next* launch finds this trail still on disk and reports it as a single
    /// consolidated log entry — turning "it just crashed" into "it crashed
    /// right after switching to Search while the library was still scanning."
    /// Deliberately NOT for high-frequency events (position ticks, scroll) —
    /// only discrete, meaningful ones; each call performs a UserDefaults write.
    nonisolated func breadcrumb(_ event: String) {
        Task { @MainActor [weak self] in self?._recordBreadcrumb(event) }
    }

    private func _recordBreadcrumb(_ event: String) {
        breadcrumbs.append("\(Date().formatted(.iso8601)) — \(event)")
        if breadcrumbs.count > maxBreadcrumbs {
            breadcrumbs.removeFirst(breadcrumbs.count - maxBreadcrumbs)
        }
        UserDefaults.standard.set(breadcrumbs, forKey: Self.breadcrumbsKey)
    }

    /// If a breadcrumb trail survived from a previous run, that session never
    /// reached a clean shutdown path (crash, force-quit, OS termination) — log
    /// what it was doing right before, then clear the trail so a normal
    /// background/terminate afterward doesn't re-report the same stale data.
    private func reportPriorSessionBreadcrumbsIfAny() {
        guard let prior = UserDefaults.standard.stringArray(forKey: Self.breadcrumbsKey),
              !prior.isEmpty
        else { return }
        let summary = prior.joined(separator: "  →  ")
        _append(LogEntry(level: "warning", category: "app",
                         message: "Possible unclean shutdown — last actions before previous session ended: \(summary)",
                         file: "AppLogger.swift", line: 0,
                         timestamp: Date().formatted(.iso8601), extra: [:]))
        UserDefaults.standard.removeObject(forKey: Self.breadcrumbsKey)
    }

    // MARK: - Public log methods (nonisolated — callable from any context)

    nonisolated func log(
        _ message: String,
        level: String = "info",
        category: String = "general",
        file: String = #file,
        line: Int = #line,
        extra: [String: String] = [:]
    ) {
        let shortFile = URL(fileURLWithPath: file).lastPathComponent
        let ts = Date().formatted(.iso8601)
        let entry = LogEntry(level: level, category: category, message: message,
                             file: shortFile, line: line, timestamp: ts, extra: extra)
        Task { @MainActor [weak self] in self?._append(entry) }
    }

    nonisolated func warn(
        _ message: String,
        category: String = "general",
        file: String = #file,
        line: Int = #line,
        extra: [String: String] = [:]
    ) {
        log(message, level: "warning", category: category, file: file, line: line, extra: extra)
    }

    nonisolated func error(
        _ message: String,
        category: String = "general",
        file: String = #file,
        line: Int = #line,
        extra: [String: String] = [:]
    ) {
        log(message, level: "error", category: category, file: file, line: line, extra: extra)
        // Flush immediately so errors are never lost if the app terminates soon after.
        Task { @MainActor [weak self] in await self?.flush() }
    }

    // MARK: - Bug Reports

    /// A short text dump of recent breadcrumbs and buffered log entries,
    /// attached to user-submitted bug reports (Settings → Help → Report a Bug)
    /// to give context without requiring the user to describe what led up to it.
    func recentActivitySummary() -> String {
        var lines: [String] = []
        if !breadcrumbs.isEmpty {
            lines.append("Recent activity:")
            lines.append(contentsOf: breadcrumbs)
        }
        let recentLogs = recentEntries.suffix(50)
        if !recentLogs.isEmpty {
            lines.append("Recent logs:")
            lines.append(contentsOf: recentLogs.map { "[\($0.level)][\($0.category)] \($0.message)" })
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - Private

    private func _append(_ entry: LogEntry) {
        var entry = entry
        // Read at append time (MainActor) rather than at the nonisolated call
        // site — `currentUser` can only be read safely here, and using the
        // value at flush time would tag entries with whoever is logged in
        // *now* rather than who triggered them.
        entry.userId = AccountService.shared?.currentUser?.id
        buffer.append(entry)
        if buffer.count > maxBuffer {
            buffer.removeFirst(buffer.count - maxBuffer)
        }

        recentEntries.append(entry)
        if recentEntries.count > maxRecentEntries {
            recentEntries.removeFirst(recentEntries.count - maxRecentEntries)
        }
        #if DEBUG
        let extra = entry.extra.isEmpty ? "" : " \(entry.extra)"
        print("[\(entry.level.uppercased())][\(entry.category)] \(entry.message)\(extra)")
        #endif
    }

    private func startFlushTimer() {
        flushTimer?.invalidate()
        flushTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { [weak self] in await self?.flush() }
        }
    }

    private func flush() async {
        guard !buffer.isEmpty, !bridgeURL.isEmpty else { return }
        let entries = buffer
        buffer.removeAll()

        let base = bridgeURL.trimmingCharacters(in: .init(charactersIn: "/"))
        guard let url = URL(string: "\(base)/internal/logs") else { return }
        var req = URLRequest(url: url, timeoutInterval: 10)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")

        do {
            req.httpBody = try JSONEncoder().encode(entries)
            let (_, resp) = try await URLSession.shared.data(for: req)
            if (resp as? HTTPURLResponse)?.statusCode != 200 {
                let requeue = entries.suffix(maxBuffer - buffer.count)
                buffer.insert(contentsOf: requeue, at: 0)
            }
        } catch {
            let requeue = entries.suffix(maxBuffer - buffer.count)
            buffer.insert(contentsOf: requeue, at: 0)
        }
    }
}

// MARK: - Global convenience shims (callable without referencing the shared instance)

/// Logs an info-level message from any context. File/line captured at call site.
func appLog(_ message: String, category: String = "general",
            file: String = #file, line: Int = #line,
            extra: [String: String] = [:]) {
    AppLogger.shared.log(message, level: "info", category: category, file: file, line: line, extra: extra)
}

func appWarn(_ message: String, category: String = "general",
             file: String = #file, line: Int = #line,
             extra: [String: String] = [:]) {
    AppLogger.shared.warn(message, category: category, file: file, line: line, extra: extra)
}

func appError(_ message: String, category: String = "general",
              file: String = #file, line: Int = #line,
              extra: [String: String] = [:]) {
    AppLogger.shared.error(message, category: category, file: file, line: line, extra: extra)
}

/// Records a short breadcrumb of a significant action for crash-context
/// reporting on the next launch. See `AppLogger.breadcrumb`.
func appBreadcrumb(_ event: String) {
    AppLogger.shared.breadcrumb(event)
}
