import WidgetKit
import SwiftUI
import AppIntents

// MARK: - Timeline Entry

struct LumisoundEntry: TimelineEntry {
    let date: Date
    let title: String
    let artist: String
    let isPlaying: Bool
    let artwork: UIImage?
}

// MARK: - Timeline Provider

struct LumisoundWidgetProvider: TimelineProvider {
    private let appGroupID = "group.com.lumisound.ios"

    func placeholder(in context: Context) -> LumisoundEntry {
        LumisoundEntry(date: Date(), title: "Track Title", artist: "Artist", isPlaying: false, artwork: nil)
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
        let isPlaying = ud?.bool(forKey: "widget_is_playing") ?? false
        var artwork: UIImage? = nil
        if let path = ud?.string(forKey: "widget_artwork_path") {
            artwork = UIImage(contentsOfFile: path)
        }
        return LumisoundEntry(date: Date(), title: title, artist: artist, isPlaying: isPlaying, artwork: artwork)
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
                    Text(entry.artist)
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.75))
                        .lineLimit(1)

                    Spacer()

                    if #available(iOS 17.0, *) {
                        HStack(spacing: 22) {
                            Button(intent: TogglePlaybackIntent()) {
                                Image(systemName: entry.isPlaying ? "pause.fill" : "play.fill")
                                    .font(.system(size: 22, weight: .semibold))
                                    .foregroundStyle(.white)
                            }
                            .buttonStyle(.plain)

                            Button(intent: SkipNextIntent()) {
                                Image(systemName: "forward.fill")
                                    .font(.system(size: 20, weight: .medium))
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

// MARK: - Entry View (dispatches to family-specific view)

struct LumisoundWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family
    let entry: LumisoundEntry

    var body: some View {
        switch family {
        case .accessoryCircular:
            WidgetCircularView(entry: entry)
        case .systemMedium:
            WidgetMediumView(entry: entry)
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
                .containerBackground(.black, for: .widget)
        }
        .configurationDisplayName("Lumisound")
        .description("Now Playing track from Lumisound.")
        .supportedFamilies([
            .systemSmall,
            .systemMedium,
            .accessoryCircular,
        ])
    }
}
