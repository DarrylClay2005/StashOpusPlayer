import AppIntents
import Foundation

// MARK: - Darwin notification names

enum WidgetNotificationNames {
    static let togglePlayback = "com.lumisound.ios.widget.togglePlayback"
    static let skipNext       = "com.lumisound.ios.widget.skipNext"
}

// MARK: - Toggle Playback

struct TogglePlaybackIntent: AppIntent {
    static let title: LocalizedStringResource = "Toggle Playback"
    static let description = IntentDescription("Play or pause Lumisound.")
    static let openAppWhenRun: Bool = false

    func perform() async throws -> some IntentResult {
        postDarwin(name: WidgetNotificationNames.togglePlayback)
        return .result()
    }
}

// MARK: - Skip Next

struct SkipNextIntent: AppIntent {
    static let title: LocalizedStringResource = "Skip to Next"
    static let description = IntentDescription("Skip to the next track in Lumisound.")
    static let openAppWhenRun: Bool = false

    func perform() async throws -> some IntentResult {
        postDarwin(name: WidgetNotificationNames.skipNext)
        return .result()
    }
}

// MARK: - Darwin post helper

private func postDarwin(name: String) {
    CFNotificationCenterPostNotification(
        CFNotificationCenterGetDarwinNotifyCenter(),
        CFNotificationName(name as CFString),
        nil, nil, true
    )
}
