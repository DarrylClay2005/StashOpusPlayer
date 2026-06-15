import WidgetKit
import SwiftUI
import AppIntents

// MARK: - Helpers

/// Applies containerBackground on iOS 17+; no-op on iOS 16.
struct WidgetBackgroundModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 17.0, *) {
            content.containerBackground(.black, for: .widget)
        } else {
            content
        }
    }
}

private func formatTime(_ seconds: TimeInterval) -> String {
    guard seconds.isFinite, seconds >= 0 else { return "0:00" }
    let total = Int(seconds)
    return String(format: "%d:%02d", total / 60, total % 60)
}

// MARK: - Timeline Entry

struct LumisoundEntry: TimelineEntry {
    let date: Date
    let title: String
    let artist: String
    let bpm: Double?
    let isPlaying: Bool
    let artwork: UIImage?
    /// Playback position (seconds) as of `anchorDate`.
    let position: TimeInterval
    let duration: TimeInterval
    /// The moment `position`/`isPlaying` were captured by the main app —
    /// lets `Text(timerInterval:)` keep ticking live between timeline reloads.
    let anchorDate: Date

    /// Date range covering the full track, anchored so "now" maps to the
    /// correct elapsed position — feeds `Text(timerInterval:)` for a
    /// live-updating elapsed time without further widget reloads.
    var trackRange: ClosedRange<Date> {
        let start = anchorDate.addingTimeInterval(-position)
        let end = start.addingTimeInterval(max(duration, position))
        return start...max(start, end)
    }
}

// MARK: - Timeline Provider

struct LumisoundWidgetProvider: TimelineProvider {
    private let appGroupID = "group.com.lumisound.ios"

    func placeholder(in context: Context) -> LumisoundEntry {
        LumisoundEntry(date: Date(), title: "Track Title", artist: "Artist", bpm: nil, isPlaying: false,
                        artwork: nil, position: 0, duration: 0, anchorDate: Date())
    }

    func getSnapshot(in context: Context, completion: @escaping (LumisoundEntry) -> Void) {
        completion(currentEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<LumisoundEntry>) -> Void) {
        // .never: the main app drives all updates via WidgetCenter.reloadAllTimelines()
        completion(Timeline(entries: [currentEntry()], policy: .never))
    }

    private func currentEntry() -> LumisoundEntry {
        let ud = UserDefaults(suiteName: appGroupID)
        let title     = ud?.string(forKey: "widget_track_title") ?? ""
        let artist    = ud?.string(forKey: "widget_track_artist") ?? ""
        let rawBPM    = ud?.double(forKey: "widget_track_bpm") ?? 0
        let bpm: Double? = rawBPM > 0 ? rawBPM : nil
        let isPlaying = ud?.bool(forKey: "widget_is_playing") ?? false
        let position  = ud?.double(forKey: "widget_position") ?? 0
        let duration  = ud?.double(forKey: "widget_duration") ?? 0
        let anchor    = ud?.double(forKey: "widget_anchor_date")
        let anchorDate = anchor.map { Date(timeIntervalSinceReferenceDate: $0) } ?? Date()
        var artwork: UIImage? = nil
        if let relPath = ud?.string(forKey: "widget_artwork_path"),
           let container = FileManager.default.containerURL(
               forSecurityApplicationGroupIdentifier: appGroupID) {
            artwork = UIImage(contentsOfFile: container.appendingPathComponent(relPath).path)
        }
        return LumisoundEntry(date: Date(), title: title, artist: artist, bpm: bpm, isPlaying: isPlaying,
                               artwork: artwork, position: position, duration: duration, anchorDate: anchorDate)
    }
}

// MARK: - Shared progress bar

/// A thin progress bar that ticks live while playing (via `Text(timerInterval:)`'s
/// underlying timer reference, recomputed from `entry.trackRange`) and stays
/// static at `position` when paused.
struct WidgetProgressBar: View {
    let entry: LumisoundEntry
    var tint: Color = .white

    var body: some View {
        GeometryReader { geo in
            let fraction = entry.duration > 0 ? min(1, max(0, entry.position / entry.duration)) : 0
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.25))
                Capsule().fill(tint)
                    .frame(width: geo.size.width * fraction)
            }
        }
        .frame(height: 3)
    }
}

/// Elapsed / remaining time labels. Uses `Text(timerInterval:)` while playing so
/// the displayed time advances on its own between the (infrequent) widget reloads.
struct WidgetTimeLabel: View {
    let entry: LumisoundEntry
    var font: Font = .system(size: 10)

    var body: some View {
        if entry.isPlaying, entry.duration > 0 {
            Text(timerInterval: entry.trackRange, countsDown: false, showsHours: false)
                .font(font)
                .monospacedDigit()
                .foregroundStyle(.white.opacity(0.75))
        } else {
            Text(formatTime(entry.position))
                .font(font)
                .monospacedDigit()
                .foregroundStyle(.white.opacity(0.75))
        }
    }
}

// MARK: - Small Widget View

struct WidgetSmallView: View {
    let entry: LumisoundEntry

    var body: some View {
        ZStack {
            if let img = entry.artwork {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
                    .blur(radius: 20)
                    .overlay(Color.black.opacity(0.5))
            } else {
                Color.black
            }

            VStack(spacing: 6) {
                if let img = entry.artwork {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 62, height: 62)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                } else {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.gray.opacity(0.35))
                        .frame(width: 62, height: 62)
                        .overlay(
                            Image(systemName: "music.note")
                                .foregroundStyle(.white.opacity(0.6))
                                .font(.system(size: 22))
                        )
                }
                Text(entry.title.isEmpty ? "Not Playing" : entry.title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(entry.artist)
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.7))
                    .lineLimit(1)
                if !entry.title.isEmpty {
                    WidgetProgressBar(entry: entry)
                }
            }
            .padding(8)
        }
    }
}

// MARK: - Medium Widget View

struct WidgetMediumView: View {
    let entry: LumisoundEntry

    var body: some View {
        ZStack {
            if let img = entry.artwork {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
                    .blur(radius: 30)
                    .overlay(Color.black.opacity(0.6))
            } else {
                Color.black
            }

            HStack(spacing: 14) {
                if let img = entry.artwork {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 80, height: 80)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                } else {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.gray.opacity(0.35))
                        .frame(width: 80, height: 80)
                        .overlay(
                            Image(systemName: "music.note")
                                .foregroundStyle(.white.opacity(0.6))
                                .font(.system(size: 28))
                        )
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(entry.title.isEmpty ? "Nothing Playing" : entry.title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                    HStack(spacing: 6) {
                        Text(entry.artist)
                            .font(.system(size: 12))
                            .foregroundStyle(.white.opacity(0.75))
                            .lineLimit(1)
                        if let bpm = entry.bpm {
                            Text("\(Int(bpm.rounded())) BPM")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(.cyan.opacity(0.9))
                                .lineLimit(1)
                        }
                    }

                    Spacer()

                    if !entry.title.isEmpty {
                        WidgetProgressBar(entry: entry)
                        HStack {
                            WidgetTimeLabel(entry: entry)
                            Spacer()
                            Text(formatTime(entry.duration))
                                .font(.system(size: 10))
                                .monospacedDigit()
                                .foregroundStyle(.white.opacity(0.75))
                        }
                    }

                    Spacer()

                    if #available(iOS 17.0, *) {
                        HStack(spacing: 22) {
                            Button(intent: SkipPreviousIntent()) {
                                Image(systemName: "backward.fill")
                                    .font(.system(size: 18, weight: .medium))
                                    .foregroundStyle(.white.opacity(0.85))
                            }
                            .buttonStyle(.plain)

                            Button(intent: TogglePlaybackIntent()) {
                                Image(systemName: entry.isPlaying ? "pause.fill" : "play.fill")
                                    .font(.system(size: 22, weight: .semibold))
                                    .foregroundStyle(.white)
                            }
                            .buttonStyle(.plain)

                            Button(intent: SkipNextIntent()) {
                                Image(systemName: "forward.fill")
                                    .font(.system(size: 18, weight: .medium))
                                    .foregroundStyle(.white.opacity(0.85))
                            }
                            .buttonStyle(.plain)
                        }
                    } else {
                        Image(systemName: entry.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(14)
        }
    }
}

// MARK: - Large Widget View

struct WidgetLargeView: View {
    let entry: LumisoundEntry

    var body: some View {
        ZStack {
            if let img = entry.artwork {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
                    .blur(radius: 40)
                    .overlay(Color.black.opacity(0.65))
            } else {
                Color.black
            }

            VStack(spacing: 16) {
                if let img = entry.artwork {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 160, height: 160)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .shadow(radius: 12)
                } else {
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color.gray.opacity(0.35))
                        .frame(width: 160, height: 160)
                        .overlay(
                            Image(systemName: "music.note")
                                .foregroundStyle(.white.opacity(0.6))
                                .font(.system(size: 44))
                        )
                }

                VStack(spacing: 2) {
                    Text(entry.title.isEmpty ? "Nothing Playing" : entry.title)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    HStack(spacing: 6) {
                        Text(entry.artist)
                            .font(.system(size: 13))
                            .foregroundStyle(.white.opacity(0.75))
                            .lineLimit(1)
                        if let bpm = entry.bpm {
                            Text("\(Int(bpm.rounded())) BPM")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.cyan.opacity(0.9))
                                .lineLimit(1)
                        }
                    }
                }

                if !entry.title.isEmpty {
                    VStack(spacing: 4) {
                        WidgetProgressBar(entry: entry)
                        HStack {
                            WidgetTimeLabel(entry: entry)
                            Spacer()
                            Text(formatTime(entry.duration))
                                .font(.system(size: 10))
                                .monospacedDigit()
                                .foregroundStyle(.white.opacity(0.75))
                        }
                    }
                }

                if #available(iOS 17.0, *) {
                    HStack(spacing: 36) {
                        Button(intent: SkipPreviousIntent()) {
                            Image(systemName: "backward.fill")
                                .font(.system(size: 22, weight: .medium))
                                .foregroundStyle(.white.opacity(0.85))
                        }
                        .buttonStyle(.plain)

                        Button(intent: TogglePlaybackIntent()) {
                            Image(systemName: entry.isPlaying ? "pause.fill" : "play.fill")
                                .font(.system(size: 30, weight: .semibold))
                                .foregroundStyle(.white)
                        }
                        .buttonStyle(.plain)

                        Button(intent: SkipNextIntent()) {
                            Image(systemName: "forward.fill")
                                .font(.system(size: 22, weight: .medium))
                                .foregroundStyle(.white.opacity(0.85))
                        }
                        .buttonStyle(.plain)
                    }
                } else {
                    Image(systemName: entry.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundStyle(.white)
                }
            }
            .padding(18)
        }
    }
}

// MARK: - Circular Lock Screen Widget View

struct WidgetCircularView: View {
    let entry: LumisoundEntry

    var body: some View {
        ZStack {
            if let img = entry.artwork {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
                    .clipShape(Circle())
                    .overlay(
                        Circle()
                            .stroke(
                                entry.isPlaying ? Color.cyan : Color.white.opacity(0.3),
                                lineWidth: 2
                            )
                    )
            } else {
                Circle()
                    .fill(Color.gray.opacity(0.35))
                    .overlay(
                        Image(systemName: "music.note")
                            .foregroundStyle(.white.opacity(0.7))
                            .font(.system(size: 16))
                    )
            }
        }
        .widgetLabel {
            Text(entry.title)
                .lineLimit(1)
        }
    }
}

// MARK: - Rectangular Lock Screen Widget View

struct WidgetRectangularView: View {
    let entry: LumisoundEntry

    var body: some View {
        HStack(spacing: 8) {
            if let img = entry.artwork {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 36, height: 36)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            } else {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.white.opacity(0.2))
                    .frame(width: 36, height: 36)
                    .overlay(Image(systemName: "music.note").font(.system(size: 14)))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.title.isEmpty ? "Nothing Playing" : entry.title)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                Text(entry.artist)
                    .font(.system(size: 11))
                    .opacity(0.7)
                    .lineLimit(1)
                if !entry.title.isEmpty {
                    WidgetProgressBar(entry: entry, tint: .cyan)
                }
            }
        }
    }
}

// MARK: - Inline Lock Screen Widget View

struct WidgetInlineView: View {
    let entry: LumisoundEntry

    var body: some View {
        if entry.title.isEmpty {
            Text("Lumisound: Nothing Playing")
        } else {
            Text("\(entry.isPlaying ? "▶" : "⏸") \(entry.title) — \(entry.artist)")
        }
    }
}

// MARK: - Entry View (dispatches to family-specific view)

struct LumisoundWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family
    let entry: LumisoundEntry

    var body: some View {
        switch family {
        case .accessoryCircular:
            WidgetCircularView(entry: entry)
        case .accessoryRectangular:
            WidgetRectangularView(entry: entry)
        case .accessoryInline:
            WidgetInlineView(entry: entry)
        case .systemMedium:
            WidgetMediumView(entry: entry)
        case .systemLarge:
            WidgetLargeView(entry: entry)
        default:
            WidgetSmallView(entry: entry)
        }
    }
}

// MARK: - Widget Configuration

@main
struct LumisoundWidget: Widget {
    let kind = "LumisoundWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: LumisoundWidgetProvider()) { entry in
            LumisoundWidgetEntryView(entry: entry)
                .modifier(WidgetBackgroundModifier())
        }
        .configurationDisplayName("Lumisound")
        .description("Now Playing track from Lumisound.")
        .supportedFamilies([
            .systemSmall,
            .systemMedium,
            .systemLarge,
            .accessoryCircular,
            .accessoryRectangular,
            .accessoryInline,
        ])
    }
}
