import Foundation

extension TimeInterval {
    /// Formats the interval as `m:ss`, e.g. `3:07`. Returns `0:00` for non-finite or negative values.
    var formattedAsMinutesSeconds: String {
        guard isFinite, self >= 0 else { return "0:00" }
        let total = Int(rounded())
        return "\(total / 60):\(String(format: "%02d", total % 60))"
    }

    /// Formats the interval as `h:mm:ss` when it spans an hour or more, otherwise `m:ss`.
    var formattedWithHours: String {
        guard isFinite, self >= 0 else { return "0:00" }
        let total = Int(rounded())
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 {
            return "\(h):\(String(format: "%02d", m)):\(String(format: "%02d", s))"
        }
        return "\(m):\(String(format: "%02d", s))"
    }
}
