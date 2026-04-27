import Foundation

struct LrcLine: Identifiable, Hashable {
    let id = UUID()
    let time: TimeInterval
    let text: String
}

enum LrcParser {
    private static let pattern = #"\[(\d{1,2}):(\d{1,2})(?:\.(\d{1,2}))?\]"#

    static func parse(_ content: String) -> [LrcLine] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        var parsed: [LrcLine] = []

        for raw in content.split(whereSeparator: \.isNewline).map(String.init) {
            let range = NSRange(raw.startIndex..<raw.endIndex, in: raw)
            let matches = regex.matches(in: raw, range: range)
            guard !matches.isEmpty else { continue }

            let text = regex.stringByReplacingMatches(in: raw, range: range, withTemplate: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)

            for match in matches {
                guard
                    let minuteRange = Range(match.range(at: 1), in: raw),
                    let secondRange = Range(match.range(at: 2), in: raw)
                else { continue }

                let minutes = TimeInterval(String(raw[minuteRange])) ?? 0
                let seconds = TimeInterval(String(raw[secondRange])) ?? 0
                var hundredths: TimeInterval = 0

                if let fractionRange = Range(match.range(at: 3), in: raw) {
                    hundredths = TimeInterval(String(raw[fractionRange])) ?? 0
                }

                parsed.append(LrcLine(time: minutes * 60 + seconds + hundredths / 100, text: text))
            }
        }

        return parsed.sorted { $0.time < $1.time }
    }
}
