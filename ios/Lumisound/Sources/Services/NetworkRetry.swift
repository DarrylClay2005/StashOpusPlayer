import Foundation

/// Shared retry/backoff helper for transient network failures. Previously, no
/// request anywhere in the app retried on its own — a single dropped packet or
/// momentary DNS hiccup surfaced immediately as a user-facing error, even for
/// idempotent GETs (search, resolve, sync pull) that are perfectly safe to retry.
///
/// Only retries errors that look transient: `URLError` codes for timeouts,
/// connection loss, and unreachable hosts, plus HTTP 408/429/5xx. Anything
/// else (4xx auth errors, decode failures, cancellation) is rethrown
/// immediately on the first attempt.
enum NetworkRetry {
    /// Runs `operation`, retrying up to `maxAttempts` times (including the
    /// first) with exponential backoff + jitter (e.g. ~0.4s, ~0.8s for the
    /// default of 3 attempts) if the error is transient.
    static func withRetry<T>(
        maxAttempts: Int = 3,
        baseDelay: TimeInterval = 0.4,
        operation: () async throws -> T
    ) async throws -> T {
        var lastError: Error?
        for attempt in 0..<maxAttempts {
            do {
                return try await operation()
            } catch {
                lastError = error
                guard attempt < maxAttempts - 1, isTransient(error) else { throw error }
                let backoff = baseDelay * pow(2, Double(attempt))
                let jitter = Double.random(in: 0...(baseDelay * 0.5))
                try? await Task.sleep(nanoseconds: UInt64((backoff + jitter) * 1_000_000_000))
            }
        }
        throw lastError ?? URLError(.unknown)
    }

    /// True for network-level hiccups and server-side 408/429/5xx — the kinds
    /// of failures where the same request a moment later commonly succeeds.
    static func isTransient(_ error: Error) -> Bool {
        if let urlError = error as? URLError {
            switch urlError.code {
            case .timedOut, .networkConnectionLost, .notConnectedToInternet,
                 .dnsLookupFailed, .cannotFindHost, .cannotConnectToHost,
                 .resourceUnavailable, .dataNotAllowed:
                return true
            default:
                return false
            }
        }
        if let httpError = error as? StreamingError, case .httpError(let status) = httpError {
            return status == 408 || status == 429 || (500...599).contains(status)
        }
        if let accountError = error as? AccountError {
            let status = accountError.statusCode
            return status == 408 || status == 429 || (500...599).contains(status)
        }
        return false
    }
}
