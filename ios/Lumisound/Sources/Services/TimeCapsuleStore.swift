import Foundation
import UserNotifications

/// A "Time Capsule" seals a snapshot of songs (from Favorites or an
/// existing playlist) plus a short note to your future self, locked until
/// a date you pick — weeks, months, even years out. Entirely on-device,
/// same persistence shape as `PlayHistoryStore`/`DownloadLedgerStore`
/// (plain Codable array in UserDefaults); the only thing it reaches outside
/// itself for is scheduling the unlock notification, which follows the
/// exact same `UNCalendarNotificationTrigger` pattern as
/// `SleepWakeAlarmService`'s wake alarm — including that same real iOS
/// limitation: the notification always fires (even from fully killed), but
/// nothing else happens automatically until the user taps it and opens the
/// capsule themselves.
struct TimeCapsule: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var message: String
    var songIDs: [Song.ID]
    var createdAt: Date
    var unlockAt: Date
    var openedAt: Date?

    var isUnlocked: Bool { Date() >= unlockAt }
}

@MainActor
final class TimeCapsuleStore: ObservableObject {
    static let shared = TimeCapsuleStore()

    private let key = "timeCapsules.v1"
    @Published private(set) var capsules: [TimeCapsule] = []

    private init() { load() }

    /// Seals a new capsule and schedules its unlock notification. `unlockAt`
    /// should be in the future — sealing one for a past date just means it
    /// shows up already unlocked, no notification fires (past dates can't
    /// be scheduled with `UNCalendarNotificationTrigger`).
    func seal(name: String, message: String, songIDs: [Song.ID], unlockAt: Date) {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty, !songIDs.isEmpty else { return }
        let capsule = TimeCapsule(
            id: UUID(), name: trimmedName, message: message, songIDs: songIDs,
            createdAt: Date(), unlockAt: unlockAt, openedAt: nil
        )
        capsules.insert(capsule, at: 0)
        save()
        if unlockAt > Date() {
            scheduleNotification(for: capsule)
        }
    }

    func markOpened(_ id: TimeCapsule.ID) {
        guard let index = capsules.firstIndex(where: { $0.id == id }) else { return }
        guard capsules[index].openedAt == nil else { return }
        capsules[index].openedAt = Date()
        save()
    }

    func delete(_ id: TimeCapsule.ID) {
        capsules.removeAll { $0.id == id }
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: [notificationIdentifier(for: id)]
        )
        save()
    }

    private func notificationIdentifier(for id: TimeCapsule.ID) -> String {
        "timeCapsule.\(id.uuidString)"
    }

    private func scheduleNotification(for capsule: TimeCapsule) {
        guard NotificationService.shared.isAuthorized else { return }
        let content = UNMutableNotificationContent()
        content.title = "A Time Capsule Just Unlocked"
        content.body = "\"\(capsule.name)\" is ready to open."
        content.sound = .default

        let components = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute], from: capsule.unlockAt
        )
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let request = UNNotificationRequest(
            identifier: notificationIdentifier(for: capsule.id), content: content, trigger: trigger
        )
        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                appWarn("TimeCapsuleStore: failed to schedule unlock notification: \(error.localizedDescription)", category: "notifications")
            }
        }
    }

    private func load() {
        if let data = UserDefaults.standard.data(forKey: key),
           let decoded = try? JSONDecoder().decode([TimeCapsule].self, from: data) {
            capsules = decoded
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(capsules) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}
