import Foundation

/// Lightweight background logger that buffers log entries and flushes them to
/// the bridge server periodically. Uses a serial queue so the main thread is
/// never blocked. If the server is unreachable, entries are kept in memory
/// (bounded buffer of 500 entries) and retried on next flush.
@MainActor
final class AppLogger: ObservableObject {
    static let shared = AppLogger()

    private struct LogEntry: Codable {
        let level: String       // "info", "warning", "error"
        let category: String    // "audio", "library", "account", "ui", "network"
        let message: String
        let file: String
        let line: Int
        let timestamp: String   // ISO8601
        var extra: [String: String] = [:]
    }

    private static let iso8601 = ISO8601DateFormatter()

    private var buffer: [LogEntry] = []
    private let maxBuffer = 500
    private var flushTimer: Timer?
    private var bridgeURL: String = ""

    private init() {}

    func configure(bridgeURL: String) {
        self.bridgeURL = bridgeURL
        startFlushTimer()
    }

    func log(
        _ message: String,
        level: String = "info",
        category: String = "general",
        file: String = #file,
        line: Int = #line,
        extra: [String: String] = [:]
    ) {
        let entry = LogEntry(
            level: level,
            category: category,
            message: message,
            file: URL(fileURLWithPath: file).lastPathComponent,
            line: line,
            timestamp: AppLogger.iso8601.string(from: Date()),
            extra: extra
        )
        buffer.append(entry)
        if buffer.count > maxBuffer { buffer.removeFirst(buffer.count - maxBuffer) }

        // Log to console in debug builds
        #if DEBUG
        print("[\(level.uppercased())][\(category)] \(message)")
        #endif
    }

    func error(_ message: String, category: String = "general",
               file: String = #file, line: Int = #line) {
        log(message, level: "error", category: category, file: file, line: line)
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
                // Re-buffer on failure (up to limit)
                let requeue = entries.suffix(maxBuffer - buffer.count)
                buffer.insert(contentsOf: requeue, at: 0)
            }
        } catch {
            // Re-buffer silently
            let requeue = entries.suffix(maxBuffer - buffer.count)
            buffer.insert(contentsOf: requeue, at: 0)
        }
    }
}
