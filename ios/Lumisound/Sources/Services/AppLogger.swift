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
    }

    // MARK: - Private state (all @MainActor)

    private var buffer: [LogEntry] = []
    private let maxBuffer = 1_000
    private var flushTimer: Timer?
    private var bridgeURL: String = ""
    private var isConfigured = false

    private init() {}

    // MARK: - Configuration

    /// Call once on app launch. Subsequent calls (e.g. from SwiftUI `.task` re-fires) are no-ops.
    func configure(bridgeURL: String) {
        guard !isConfigured else { return }
        isConfigured = true
        self.bridgeURL = bridgeURL
        _append(LogEntry(level: "info", category: "app", message: "App launched",
                         file: "LumisoundApp.swift", line: 0,
                         timestamp: Date().formatted(.iso8601), extra: [:]))
        startFlushTimer()
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

    // MARK: - Private

    private func _append(_ entry: LogEntry) {
        buffer.append(entry)
        if buffer.count > maxBuffer {
            buffer.removeFirst(buffer.count - maxBuffer)
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
