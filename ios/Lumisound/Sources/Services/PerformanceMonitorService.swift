import Darwin
import Foundation
import MetricKit

// MARK: - PerformanceMonitorService

/// Always-on CPU/GPU resource-usage logging — no settings toggle, starts
/// automatically at launch. Every `AppLogger` entry already auto-attaches
/// `DeviceInfo.modelIdentifier`/`.osVersion` (see `AppLogger.LogEntry`), so
/// logging through `appLog(..., category: "performance")` gets "categorized
/// by device and iOS number" for free — no extra plumbing needed here.
///
/// Two independent sources, since no single public iOS API covers both CPU
/// and GPU in real time:
///  1. `CPUSampler` — coarse system-wide CPU load every 60s via Darwin's
///     `host_cpu_load_info`, the same counters `top`/Activity Monitor read.
///  2. `MetricSubscriber` — Apple's own MetricKit daily aggregate, which is
///     the ONLY public API surface exposing GPU usage on iOS at all; there
///     is no real-time per-frame GPU-utilization query available to apps.
enum PerformanceMonitorService {
    /// Call once from `LumisoundApp.init()`, alongside the other `.register()`
    /// calls — must be set up before/at launch so MetricKit doesn't miss the
    /// registration window and so CPU sampling covers the whole session.
    static func start() {
        CPUSampler.shared.start()
        MXMetricManager.shared.add(MetricSubscriber.shared)
    }
}

// MARK: - CPUSampler (periodic system CPU load)

/// Samples system-wide CPU load (not just this process) every 60s via
/// `host_cpu_load_info` — cumulative tick counts since boot, diffed between
/// two samples to get a per-interval percentage, same technique `top` uses.
private final class CPUSampler {
    static let shared = CPUSampler()

    private var timer: Timer?
    private var lastTicks: host_cpu_load_info_data_t?

    func start() {
        guard timer == nil else { return }
        sample() // seeds `lastTicks` immediately rather than waiting 60s for a first reading
        let t = Timer(timeInterval: 60, repeats: true) { [weak self] _ in
            self?.sample()
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func sample() {
        guard let ticks = Self.currentTicks() else { return }
        defer { lastTicks = ticks }
        guard let last = lastTicks else { return }

        // Double subtraction (never traps on underflow) rather than raw
        // UInt32 arithmetic — the tick counters are monotonic in practice,
        // but this stays safe even across the rare edge case (counter
        // wraparound after a very long uptime) instead of crashing.
        let userDelta = Double(ticks.cpu_ticks.0) - Double(last.cpu_ticks.0)
        let systemDelta = Double(ticks.cpu_ticks.1) - Double(last.cpu_ticks.1)
        let idleDelta = Double(ticks.cpu_ticks.2) - Double(last.cpu_ticks.2)
        let niceDelta = Double(ticks.cpu_ticks.3) - Double(last.cpu_ticks.3)
        let total = userDelta + systemDelta + idleDelta + niceDelta
        guard total > 0 else { return }

        let userPct = userDelta / total * 100
        let systemPct = systemDelta / total * 100
        let idlePct = idleDelta / total * 100

        appLog(
            String(format: "CPU load — user %.1f%% system %.1f%% idle %.1f%%", userPct, systemPct, idlePct),
            category: "performance",
            extra: [
                "cpuUserPct": String(format: "%.1f", userPct),
                "cpuSystemPct": String(format: "%.1f", systemPct),
                "cpuIdlePct": String(format: "%.1f", idlePct),
                "thermalState": ProcessInfo.processInfo.thermalState.lumisoundDescription,
            ]
        )
    }

    private static func currentTicks() -> host_cpu_load_info_data_t? {
        var size = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.stride / MemoryLayout<integer_t>.stride)
        var info = host_cpu_load_info_data_t()
        let result = withUnsafeMutablePointer(to: &info) { ptr -> kern_return_t in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(size)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &size)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        return info
    }
}

private extension ProcessInfo.ThermalState {
    var lumisoundDescription: String {
        switch self {
        case .nominal: return "nominal"
        case .fair: return "fair"
        case .serious: return "serious"
        case .critical: return "critical"
        @unknown default: return "unknown"
        }
    }
}

// MARK: - MetricSubscriber (Apple's own daily CPU/GPU aggregate)

/// Receives `MXMetricPayload`s — delivered by the OS roughly once per day,
/// each summarizing the previous ~24h window's cumulative CPU time, GPU
/// time, and thermal-state exposure for this app specifically. This is
/// Apple's intended mechanism for exactly this kind of field performance
/// monitoring; there's no faster or more granular public API for GPU usage
/// on iOS, so a daily rollup (rather than a live percentage) is the honest
/// ceiling of what's queryable here.
private final class MetricSubscriber: NSObject, MXMetricManagerSubscriber {
    static let shared = MetricSubscriber()

    func didReceive(_ payloads: [MXMetricPayload]) {
        for payload in payloads {
            var extra: [String: String] = [
                "periodStart": Self.iso(payload.timeStampBegin),
                "periodEnd": Self.iso(payload.timeStampEnd),
            ]
            if let cpu = payload.cpuMetric?.cumulativeCPUTime {
                extra["cumulativeCPUTimeSeconds"] = String(format: "%.1f", cpu.converted(to: .seconds).value)
            }
            if let gpu = payload.gpuMetric?.cumulativeGPUTime {
                extra["cumulativeGPUTimeSeconds"] = String(format: "%.1f", gpu.converted(to: .seconds).value)
            }
            appLog("MetricKit daily CPU/GPU report", category: "performance", extra: extra)
        }
    }

    private static func iso(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }
}
