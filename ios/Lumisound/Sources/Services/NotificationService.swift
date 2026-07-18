import Foundation
import Combine
import UIKit
import UserNotifications

// MARK: - NotificationService
//
// Real on-device notifications via `UNUserNotificationCenter`. Uses LOCAL
// notifications (no Apple Push certificate / APNs entitlement required), which
// is sufficient to actually deliver alerts to the user's device — both while
// the app is backgrounded and, for in-app events, immediately. Real remote
// (APNs) delivery is also wired up for background "download_ready" pushes —
// see `registerForRemoteNotifications()` below and `AppDelegate`.
//
// Two delivery paths:
//   1. In-app events (download finished, achievement unlocked, sleep-timer
//      expiry, update available) call `notify(...)` directly.
//   2. Server-side inbox notifications (GET /user/notifications — achievements,
//      artist uploads, collaborator activity) are mirrored to a device
//      notification exactly once via `syncServerNotifications(_:)`, which
//      dedupes against the set of ids it has already surfaced.
//
// Every notification is additionally gated on a per-topic preference (see
// NotificationTopic.swift / SettingsView+NotificationsSection.swift) — a topic
// resolves either from an explicit `topic:` id passed to `notify(...)`, or —
// for the handful of call sites in files this workstream doesn't own and
// can't edit (StreamSearchView+StreamingActions.swift, AchievementsView.swift)
// — inferred from the notification's identifier prefix. New call sites
// should always pass `topic:` explicitly instead of relying on inference.

@MainActor
final class NotificationService: ObservableObject {

    static let shared = NotificationService()

    /// Master user toggle (Settings → Notifications). When off, `notify` and
    /// `syncServerNotifications` become no-ops. Persisted in UserDefaults.
    @Published var isEnabled: Bool {
        didSet { UserDefaults.standard.set(isEnabled, forKey: Keys.enabled) }
    }

    /// Whether the OS-level authorization has been granted. Updated by
    /// `requestAuthorization()` / `refreshAuthorizationStatus()`.
    @Published private(set) var isAuthorized = false

    /// Per-topic on/off preferences, keyed by `NotificationTopic.id`. Absent
    /// keys fall back to that topic's `defaultEnabled`. Persisted as JSON
    /// (rather than one `@AppStorage` bool per topic) so newly-registered
    /// topics — including ones added later by other workstreams via
    /// `NotificationTopicRegistry.register(_:)` — need no migration.
    @Published private(set) var topicPreferences: [String: Bool]

    /// Set when the last `requestAuthorization()`/foreground refresh actually
    /// failed to reach the OS (as opposed to the user simply having denied
    /// permission) — surfaced in Settings so a real failure isn't silent.
    @Published private(set) var lastAuthorizationError: String?

    private enum Keys {
        static let enabled = "notifications_enabled"
        static let surfacedIDs = "notifications_surfaced_ids_v1"
        static let topicPreferences = "notifications_topic_preferences_v1"
    }

    /// Server notification ids already mirrored to a device notification, so a
    /// repeated `/user/notifications` fetch doesn't re-alert for the same item.
    private var surfacedServerIDs: Set<String>

    private var cancellables: Set<AnyCancellable> = []

    /// Guards `attachAccountLoginObserverIfNeeded()` so it only subscribes
    /// once it actually succeeds.
    private var isObservingAccountLogin = false

    private init() {
        // Default ON the first time (no stored value) so notifications work out
        // of the box once authorization is granted.
        if UserDefaults.standard.object(forKey: Keys.enabled) == nil {
            isEnabled = true
        } else {
            isEnabled = UserDefaults.standard.bool(forKey: Keys.enabled)
        }
        if let data = UserDefaults.standard.data(forKey: Keys.surfacedIDs),
           let decoded = try? JSONDecoder().decode(Set<String>.self, from: data) {
            surfacedServerIDs = decoded
        } else {
            surfacedServerIDs = []
        }
        if let data = UserDefaults.standard.data(forKey: Keys.topicPreferences),
           let decoded = try? JSONDecoder().decode([String: Bool].self, from: data) {
            topicPreferences = decoded
        } else {
            topicPreferences = [:]
        }

        // Re-check OS authorization whenever the app returns to the
        // foreground. Without this, a user who denies the permission prompt,
        // later flips it on in iOS Settings, then switches back to
        // Lumisound never actually gets re-registered for remote
        // notifications (and any "authorization needed" banner in Settings
        // stays stuck showing denied) until the app happens to relaunch.
        NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)
            .sink { [weak self] _ in
                Task { @MainActor in
                    await self?.requestAuthorization()
                }
            }
            .store(in: &cancellables)

        // Best-effort now — see `attachAccountLoginObserverIfNeeded()`'s doc
        // comment for why this can't be relied on alone and is retried from
        // `requestAuthorization()`.
        attachAccountLoginObserverIfNeeded()
    }

    /// Subscribes to `AccountService.isLoggedIn` so a login occurring after
    /// this instance was created re-sends this device's cached APNs token
    /// (see `resendStoredPushTokenIfNeeded()`'s doc comment for the bug this
    /// fixes). Not called only from `init`: `AccountService.shared` is a
    /// `weak static var` set by `AccountService`'s own `init()` — since
    /// `NotificationService.shared` is a lazily-created singleton, there's no
    /// guarantee `AccountService`'s instance already exists the first time
    /// something touches `NotificationService.shared` (property-wrapper
    /// default-value evaluation order between two independent singletons
    /// isn't something to rely on). So this is re-attempted from
    /// `requestAuthorization()`, which — per `LumisoundApp`'s launch
    /// sequence — always runs after `AccountService` is constructed, making
    /// that a reliable place to retry until it actually attaches once.
    private func attachAccountLoginObserverIfNeeded() {
        guard !isObservingAccountLogin, let account = AccountService.shared else { return }
        isObservingAccountLogin = true
        account.$isLoggedIn
            .removeDuplicates()
            .sink { loggedIn in
                guard loggedIn else { return }
                Task { await AccountService.shared?.resendStoredPushTokenIfNeeded() }
            }
            .store(in: &cancellables)
    }

    /// Whether the given topic id is currently enabled — unknown ids (e.g. a
    /// topic id typo, or one registered by a workstream whose code hasn't run
    /// yet) default to allowed, so a missing preference never silently
    /// swallows a notification.
    func isTopicEnabled(_ id: String) -> Bool {
        if let stored = topicPreferences[id] { return stored }
        return NotificationTopicRegistry.topic(for: id)?.defaultEnabled ?? true
    }

    func setTopicEnabled(_ enabled: Bool, for id: String) {
        topicPreferences[id] = enabled
        persistTopicPreferences()
    }

    private func persistTopicPreferences() {
        if let data = try? JSONEncoder().encode(topicPreferences) {
            UserDefaults.standard.set(data, forKey: Keys.topicPreferences)
        }
    }

    // MARK: - Authorization

    /// Requests alert/sound/badge authorization if not already determined, and
    /// records the result. Safe to call repeatedly (e.g. on every launch, and
    /// on every foreground return — see the `didBecomeActiveNotification`
    /// subscription in `init`).
    func requestAuthorization() async {
        // Retried here (rather than only in `init`) since this is guaranteed
        // to run after `AccountService` exists — see
        // `attachAccountLoginObserverIfNeeded()`'s doc comment.
        attachAccountLoginObserverIfNeeded()

        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        lastAuthorizationError = nil
        switch settings.authorizationStatus {
        case .notDetermined:
            do {
                isAuthorized = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            } catch {
                // Previously swallowed via `try?` — a genuine OS-level
                // failure (as opposed to the user simply tapping "Don't
                // Allow") looked identical to a normal denial, so there was
                // no way to tell the user "something went wrong, try again"
                // versus "you said no". Surface it distinctly.
                isAuthorized = false
                lastAuthorizationError = error.localizedDescription
                appWarn("NotificationService.requestAuthorization failed: \(error.localizedDescription)", category: "notifications")
            }
        case .authorized, .provisional, .ephemeral:
            isAuthorized = true
        default:
            isAuthorized = false
        }
        // Ask the OS for an APNs device token whenever we hold real alert
        // authorization, so real (background) push delivery stays wired up
        // to the current authorization state on every launch/foreground
        // return — registering again with an already-valid token is a
        // harmless no-op, and this is also what re-arms remote-notification
        // delivery for a device that only granted permission after an
        // earlier denial (see the foreground-refresh subscription above).
        if isAuthorized {
            UIApplication.shared.registerForRemoteNotifications()
        }
    }

    /// Re-reads the current OS authorization status without prompting.
    func refreshAuthorizationStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        isAuthorized = [.authorized, .provisional, .ephemeral].contains(settings.authorizationStatus)
    }

    // MARK: - Posting

    /// Identifier-prefix → topic-id inference, used only when a call site
    /// doesn't pass `topic:` explicitly. Exists because a couple of existing
    /// `notify(...)` call sites live in files this workstream doesn't own and
    /// isn't allowed to edit directly (StreamSearchView+StreamingActions.swift
    /// for downloads, AchievementsView.swift for badges) — inferring from
    /// their already-established identifier convention lets the new granular
    /// toggles apply to them retroactively with zero changes to those files.
    /// Any *new* call site should pass `topic:` explicitly instead of relying
    /// on this.
    private static let identifierPrefixTopics: [(prefix: String, topic: String)] = [
        ("download-", "download_complete"),
        ("badge-", "achievements"),
    ]

    private func inferredTopic(fromIdentifier identifier: String) -> String? {
        Self.identifierPrefixTopics.first { identifier.hasPrefix($0.prefix) }?.topic
    }

    /// Posts a local notification now (a 0.1s trigger so it delivers reliably
    /// even from the foreground). No-op when the user has notifications
    /// disabled, authorization wasn't granted, or the resolved topic is
    /// individually toggled off in Settings → Notifications.
    ///
    /// - Parameters:
    ///   - topic: The `NotificationTopic.id` this notification belongs to,
    ///     for per-category preference gating. Pass this explicitly for any
    ///     new call site. When `nil`, falls back to inferring from
    ///     `identifier`'s prefix (see `inferredTopic`), and if that also
    ///     comes up empty, the notification is only gated by the master
    ///     toggle — never silently dropped for lack of a topic.
    ///   - categoryID: Apple's `UNNotificationCategory` identifier (for
    ///     actionable notification buttons) — an unrelated concept from
    ///     `topic`. Currently no categories are registered anywhere in the
    ///     app (see the AppDelegate note in this workstream's summary), so
    ///     this is inert today but kept for forward compatibility.
    func notify(
        title: String,
        body: String,
        identifier: String = UUID().uuidString,
        topic: String? = nil,
        categoryID: String? = nil
    ) {
        guard isEnabled, isAuthorized else { return }
        let resolvedTopic = topic ?? inferredTopic(fromIdentifier: identifier)
        if let resolvedTopic, !isTopicEnabled(resolvedTopic) { return }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        if let categoryID { content.categoryIdentifier = categoryID }

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 0.1, repeats: false)
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                appWarn("NotificationService.notify failed: \(error.localizedDescription)", category: "notifications")
            }
        }
    }

    // MARK: - Server Inbox Mirroring

    /// Server-side notification `type` (see `AppNotification.type`) → topic
    /// id, for gating mirrored inbox items the same way as any other
    /// notification. Unrecognized/future server types intentionally fall
    /// through to `nil` (allowed, master-toggle-only) rather than being
    /// silently dropped.
    private static let serverTypeTopics: [String: String] = [
        "achievement": "achievements",
        "subscription": "subscription_new_content",
        "upload": "subscription_new_content",
        "collaborator": "social_activity",
        "playlist_shared": "social_activity",
    ]

    /// Fires a device notification for any server inbox item not yet surfaced.
    /// Caller passes the freshly-fetched `/user/notifications` list (typically
    /// the unread ones). Already-surfaced ids are skipped so re-fetching never
    /// double-alerts.
    func syncServerNotifications(_ notifications: [AppNotification]) {
        guard isEnabled, isAuthorized else { return }
        var didChange = false
        for notification in notifications where notification.isUnread && !surfacedServerIDs.contains(notification.id) {
            notify(
                title: notification.title,
                body: notification.body ?? "",
                identifier: "server-\(notification.id)",
                topic: Self.serverTypeTopics[notification.type]
            )
            surfacedServerIDs.insert(notification.id)
            didChange = true
        }
        // Cap the dedupe set so it can't grow unbounded across the app's life.
        if surfacedServerIDs.count > 500 {
            surfacedServerIDs = Set(surfacedServerIDs.suffix(500))
            didChange = true
        }
        if didChange { persistSurfacedIDs() }
    }

    private func persistSurfacedIDs() {
        if let data = try? JSONEncoder().encode(surfacedServerIDs) {
            UserDefaults.standard.set(data, forKey: Keys.surfacedIDs)
        }
    }
}
