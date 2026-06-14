import SwiftUI

/// Presets for how the elapsed/remaining playtime is displayed below the
/// seeker in Now Playing. Independent of `SeekerStyle` (which controls the
/// scrubber itself) — this controls the summary text row beneath it.
enum PlaytimeCounterStyle: String, CaseIterable, Identifiable {
    case elapsedRemaining
    case elapsedOnly
    case remainingOnly
    case totalDuration
    case percentage
    case fraction

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .elapsedRemaining: return "Elapsed / Remaining"
        case .elapsedOnly:      return "Elapsed"
        case .remainingOnly:    return "Remaining"
        case .totalDuration:    return "Total Length"
        case .percentage:       return "Percentage"
        case .fraction:         return "Position / Total"
        }
    }

    var iconName: String {
        switch self {
        case .elapsedRemaining: return "arrow.left.and.right"
        case .elapsedOnly:      return "hourglass.bottomhalf.filled"
        case .remainingOnly:    return "hourglass.tophalf.fill"
        case .totalDuration:    return "clock"
        case .percentage:       return "percent"
        case .fraction:         return "number"
        }
    }

    /// Returns the text to display for the given playback position/duration.
    func text(position: TimeInterval, duration: TimeInterval) -> String {
        let remaining = max(0, duration - position)
        switch self {
        case .elapsedRemaining:
            return "\(Self.formatTime(position)) · -\(Self.formatTime(remaining))"
        case .elapsedOnly:
            return Self.formatTime(position)
        case .remainingOnly:
            return "-\(Self.formatTime(remaining))"
        case .totalDuration:
            return Self.formatTime(duration)
        case .percentage:
            guard duration > 0 else { return "0%" }
            return "\(Int((position / duration * 100).rounded()))%"
        case .fraction:
            return "\(Self.formatTime(position)) / \(Self.formatTime(duration))"
        }
    }

    private static func formatTime(_ t: TimeInterval) -> String {
        guard t.isFinite, t >= 0 else { return "0:00" }
        let total = Int(t.rounded())
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 {
            return "\(h):\(String(format: "%02d", m)):\(String(format: "%02d", s))"
        }
        return "\(m):\(String(format: "%02d", s))"
    }
}
