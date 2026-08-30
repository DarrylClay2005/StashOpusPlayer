import WidgetKit
import SwiftUI

// MARK: - Lumisound Watch Complication
//
// A WidgetKit complication for the watch face, mirroring the same
// TimelineProvider/Entry/per-family-view pattern already used by the iOS
// widget (see LumisoundWidget/Sources/LumisoundWidget.swift): a
// `TimelineProvider` reads shared state, an `Entry` carries it, and a
// per-`widgetFamily` view dispatches to the right layout.
//
// Data source: this target is a SEPARATE Xcode target/process from
// `LumisoundWatch` (the main watch app), so it can't import that app's
// classes directly — same relationship as LumisoundWidget vs. Lumisound on
// iOS. It reads the same `group.com.lumisound.ios` app-group UserDefaults
// keys that `WatchWidgetDataService` (in LumisoundWatch/Sources) writes
// whenever Now Playing state changes, whether that's a phone mirror (via
// WatchConnectivityManager) or standalone on-watch playback (via
// WatchLocalPlayerManager).
//
// IMPORTANT: this is the watch's own, LOCAL app-group container — a
// completely separate physical container from the iPhone's app group of the
// same name. There is no automatic cross-device sync of app-group storage;
// the watch app is the only thing that can populate this container on the
// watch side.
//
// This target does not exist in project.yml yet — see the task report for
// the exact target block needed (type app-extension, platform watchOS,
// bundle id, entitlements, sources).

// MARK: - Timeline Entry

struct LumisoundWatchEntry: TimelineEntry {
    let date: Date
    let title: String
    let artist: String
    let isPlaying: Bool
}

// MARK: - Timeline Provider

struct LumisoundWatchProvider: TimelineProvider {
    private let appGroupID = AppGroup.id

    func placeholder(in context: Context) -> LumisoundWatchEntry {
        LumisoundWatchEntry(date: Date(), title: "Track Title", artist: "Artist", isPlaying: false)
    }

    func getSnapshot(in context: Context, completion: @escaping (LumisoundWatchEntry) -> Void) {
        completion(currentEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<LumisoundWatchEntry>) -> Void) {
        // .never: the main watch app drives all reloads via
        // WidgetCenter.shared.reloadAllTimelines() — see WatchWidgetDataService.
        completion(Timeline(entries: [currentEntry()], policy: .never))
    }

    private func currentEntry() -> LumisoundWatchEntry {
        let ud = UserDefaults(suiteName: appGroupID)
        let title = ud?.string(forKey: "watch_widget_title") ?? ""
        let artist = ud?.string(forKey: "watch_widget_artist") ?? ""
        let isPlaying = ud?.bool(forKey: "watch_widget_is_playing") ?? false
        return LumisoundWatchEntry(date: Date(), title: title, artist: artist, isPlaying: isPlaying)
    }
}

// MARK: - Family views

struct LumisoundWatchCircularView: View {
    let entry: LumisoundWatchEntry

    var body: some View {
        ZStack {
            AccessoryWidgetBackground()
            Image(systemName: entry.isPlaying ? "waveform" : "music.note")
                .font(.system(size: 20))
        }
        .widgetLabel {
            Text(entry.title.isEmpty ? "Lumisound" : entry.title)
                .lineLimit(1)
        }
    }
}

struct LumisoundWatchRectangularView: View {
    let entry: LumisoundWatchEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(entry.title.isEmpty ? "Nothing Playing" : entry.title)
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
            Text(entry.artist)
                .font(.system(size: 11))
                .opacity(0.7)
                .lineLimit(1)
            if !entry.title.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: entry.isPlaying ? "play.fill" : "pause.fill")
                        .font(.system(size: 9))
                    Text(entry.isPlaying ? "Playing" : "Paused")
                        .font(.system(size: 9))
                }
                .opacity(0.6)
            }
        }
    }
}

struct LumisoundWatchInlineView: View {
    let entry: LumisoundWatchEntry

    var body: some View {
        if entry.title.isEmpty {
            Text("Lumisound")
        } else {
            Text("\(entry.isPlaying ? "▶" : "⏸") \(entry.title) — \(entry.artist)")
        }
    }
}

struct LumisoundWatchCornerView: View {
    let entry: LumisoundWatchEntry

    var body: some View {
        Image(systemName: entry.isPlaying ? "waveform" : "music.note")
            .widgetLabel {
                Text(entry.title.isEmpty ? "Lumisound" : entry.title)
                    .lineLimit(1)
            }
    }
}

// MARK: - Entry View (dispatches to family-specific view)

struct LumisoundWatchEntryView: View {
    @Environment(\.widgetFamily) private var family
    let entry: LumisoundWatchEntry

    var body: some View {
        switch family {
        case .accessoryRectangular:
            LumisoundWatchRectangularView(entry: entry)
        case .accessoryInline:
            LumisoundWatchInlineView(entry: entry)
        case .accessoryCorner:
            LumisoundWatchCornerView(entry: entry)
        default:
            LumisoundWatchCircularView(entry: entry)
        }
    }
}

// MARK: - Widget Configuration

struct LumisoundWatchWidget: Widget {
    let kind = "LumisoundWatchWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: LumisoundWatchProvider()) { entry in
            LumisoundWatchEntryView(entry: entry)
        }
        .configurationDisplayName("Lumisound")
        .description("Now Playing track from Lumisound.")
        .supportedFamilies([
            .accessoryCircular,
            .accessoryRectangular,
            .accessoryInline,
            .accessoryCorner,
        ])
    }
}

// MARK: - Widget Bundle Entry Point

@main
struct LumisoundWatchWidgetBundle: WidgetBundle {
    var body: some Widget {
        LumisoundWatchWidget()
    }
}
