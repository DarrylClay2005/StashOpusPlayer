import Foundation

// MARK: - NotificationTopic
//
// A single toggleable notification type, shown as one row in
// Settings → Notifications (see SettingsView+NotificationsSection.swift).
// Deliberately a plain struct + open registry — not a closed `enum` — so
// other feature areas (e.g. a future social/friends surface adding "Friend
// Request" / "Friend Online" / "Friend Activity") can register brand new
// topics at runtime via `NotificationTopicRegistry.register(_:)` without
// editing this file or restructuring anything here. `NotificationService`
// gates every notification it sends on the per-topic preference recorded
// against a topic's stable `id`, so any topic — built-in or registered
// later by another workstream — is automatically toggleable the moment it's
// registered, with no further plumbing.
//
// Note: this is a distinct concept from `UNNotificationCategory` (Apple's
// actionable-notification-buttons category, referenced elsewhere as
// `categoryID`/`UNMutableNotificationContent.categoryIdentifier`). A
// `NotificationTopic.id` is purely a local persistence/grouping key for the
// user-facing toggle; it is never sent to APNs or the OS.
struct NotificationTopic: Identifiable, Hashable {
    /// Stable key used both for `UserDefaults` persistence and for matching
    /// server-driven notification `type` strings / local identifier prefixes
    /// back to a topic. Treat as append-only — don't rename existing ids,
    /// or users' saved preferences for them will silently reset to default.
    let id: String
    let group: NotificationTopicGroup
    let displayName: String
    /// One or two lines shown under the toggle explaining what it covers.
    let detail: String
    let icon: String
    let defaultEnabled: Bool

    static func == (lhs: NotificationTopic, rhs: NotificationTopic) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

// MARK: - NotificationTopicGroup

/// Visual grouping only — purely cosmetic section headers in the Settings UI.
enum NotificationTopicGroup: String, CaseIterable, Identifiable, Hashable {
    case downloads
    case library
    case listening
    case social
    case system

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .downloads: return "Downloads"
        case .library:   return "Library"
        case .listening: return "Listening"
        case .social:    return "Social"
        case .system:    return "System"
        }
    }

    var icon: String {
        switch self {
        case .downloads: return "arrow.down.circle"
        case .library:   return "music.note.list"
        case .listening: return "waveform"
        case .social:    return "person.2"
        case .system:    return "gearshape"
        }
    }
}

// MARK: - NotificationTopicRegistry

/// The full set of topics available to toggle, built-in + anything another
/// feature area has registered at runtime.
enum NotificationTopicRegistry {

    /// Topics this app ships with out of the box.
    static let builtIn: [NotificationTopic] = [
        NotificationTopic(
            id: "download_complete",
            group: .downloads,
            displayName: "Download Complete",
            detail: "A streamed track finished downloading and was added to your library.",
            icon: "checkmark.circle",
            defaultEnabled: true
        ),
        NotificationTopic(
            id: "download_failed",
            group: .downloads,
            displayName: "Download Failed",
            detail: "A download couldn't finish — network issue, blocked source, or storage full.",
            icon: "xmark.circle",
            defaultEnabled: true
        ),
        NotificationTopic(
            id: "background_import",
            group: .library,
            displayName: "Background Scan & Import",
            detail: "A library rescan, metadata sync, or background import finished.",
            icon: "arrow.triangle.2.circlepath",
            defaultEnabled: true
        ),
        NotificationTopic(
            id: "subscription_new_content",
            group: .library,
            displayName: "New Content from Follows",
            detail: "A followed channel/artist or tracked playlist has new uploads available.",
            icon: "person.crop.circle.badge.plus",
            defaultEnabled: true
        ),
        NotificationTopic(
            id: "sleep_timer_ending",
            group: .listening,
            displayName: "Sleep Timer Ending",
            detail: "Your Sleep Timer finished counting down and playback is fading out.",
            icon: "moon.zzz",
            defaultEnabled: true
        ),
        NotificationTopic(
            id: "achievements",
            group: .listening,
            displayName: "Achievements",
            detail: "You've unlocked a new badge or listening milestone.",
            icon: "trophy",
            defaultEnabled: true
        ),
        NotificationTopic(
            id: "system_alerts",
            group: .system,
            displayName: "System & Server Alerts",
            detail: "Bridge/server connectivity issues, storage warnings, and other app-health alerts.",
            icon: "exclamationmark.triangle",
            defaultEnabled: true
        ),
        // Placeholder for the social-ecosystem workstream. It can either
        // repurpose this single toggle, or (preferred, since it's more
        // granular) call `NotificationTopicRegistry.register(_:)` with its
        // own topics — e.g. "friend_request", "friend_online",
        // "friend_activity" — under `.social`, at app startup, with zero
        // changes needed here.
        NotificationTopic(
            id: "social_activity",
            group: .social,
            displayName: "Friends & Social Activity",
            detail: "Friend requests, friends coming online, and activity from people you follow.",
            icon: "person.2.wave.2",
            defaultEnabled: true
        ),
    ]

    /// Topics registered at runtime by other feature areas.
    private static var registered: [NotificationTopic] = []

    /// Adds a new toggleable topic. Safe to call multiple times/at any point
    /// during app launch — duplicate ids (matched against everything already
    /// known, built-in or registered) are ignored so this can't double-add
    /// across relaunches or repeated setup calls.
    static func register(_ topic: NotificationTopic) {
        guard !all.contains(where: { $0.id == topic.id }) else { return }
        registered.append(topic)
    }

    /// Every known topic, built-in first, in registration order.
    static var all: [NotificationTopic] { builtIn + registered }

    static func topic(for id: String) -> NotificationTopic? {
        all.first { $0.id == id }
    }

    /// Topics grouped for display, in `NotificationTopicGroup`'s declared
    /// order, skipping any group with nothing in it.
    static var grouped: [(group: NotificationTopicGroup, topics: [NotificationTopic])] {
        NotificationTopicGroup.allCases.compactMap { group in
            let topics = all.filter { $0.group == group }
            return topics.isEmpty ? nil : (group, topics)
        }
    }
}
