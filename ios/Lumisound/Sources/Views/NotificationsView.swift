import SwiftUI

// MARK: - NotificationsView
//
// In-app notification inbox (GET /user/notifications). Notifications are
// created server-side for things like new achievements, artist uploads
// (subscriptions), and collaborator activity.

struct NotificationsView: View {
    @EnvironmentObject private var account: AccountService
    @ObservedObject private var notificationService = NotificationService.shared

    @State private var notifications: [AppNotification] = []
    @State private var isLoading = false

    var body: some View {
        List {
            Section {
                Toggle(isOn: $notificationService.isEnabled) {
                    Label("Device Notifications", systemImage: "bell.badge")
                        .foregroundStyle(AppTheme.textPrimary)
                }
                .tint(AppTheme.dynamicAccent)

                if notificationService.isEnabled && !notificationService.isAuthorized {
                    Text("Notifications are turned off in iOS Settings for Lumisound. Enable them in Settings › Lumisound › Notifications to receive alerts.")
                        .font(.caption)
                        .foregroundStyle(AppTheme.warning)
                }
            } footer: {
                Text("Get alerts on your device for achievements, new artist uploads you follow, shared-playlist activity, and finished downloads.")
                    .font(AppTheme.bodyFont(size: 12))
                    .foregroundStyle(AppTheme.textSecondary)
            }
            .listRowBackground(AppTheme.surface)

            if isLoading && notifications.isEmpty {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
                .listRowBackground(Color.clear)
            } else if notifications.isEmpty {
                EmptyStateView(
                    icon: "bell",
                    title: "No notifications",
                    message: "Updates about achievements, subscriptions, and shared playlists will show up here."
                )
                .listRowBackground(Color.clear)
            } else {
                ForEach(notifications) { notification in
                    HStack(alignment: .top, spacing: 10) {
                        Circle()
                            .fill(notification.isUnread ? AppTheme.dynamicAccent : Color.clear)
                            .frame(width: 8, height: 8)
                            .padding(.top, 5)

                        VStack(alignment: .leading, spacing: 3) {
                            Text(notification.title)
                                .foregroundStyle(AppTheme.textPrimary)
                            if let body = notification.body, !body.isEmpty {
                                Text(body)
                                    .font(.caption)
                                    .foregroundStyle(AppTheme.textSecondary)
                            }
                            if let date = relativeDate(notification.createdAt) {
                                Text(date)
                                    .font(.caption2)
                                    .foregroundStyle(AppTheme.textSecondary.opacity(0.7))
                            }
                        }
                    }
                    .padding(.vertical, 4)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        guard notification.isUnread else { return }
                        markRead(notification)
                    }
                    .listRowBackground(AppTheme.surface.opacity(0.5))
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Color.clear.ignoresSafeArea())
        .navigationTitle("Notifications")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if notifications.contains(where: { $0.isUnread }) {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Mark All Read") {
                        markAllRead()
                    }
                    .tint(AppTheme.dynamicAccent)
                }
            }
        }
        .task {
            await notificationService.requestAuthorization()
            await load()
        }
        .refreshable { await load() }
    }

    private func load() async {
        isLoading = true
        notifications = await account.fetchNotifications()
        // Mirror any unread server-inbox items to device notifications (deduped
        // so opening this screen repeatedly doesn't re-alert).
        NotificationService.shared.syncServerNotifications(notifications)
        isLoading = false
    }

    private func markRead(_ notification: AppNotification) {
        guard let index = notifications.firstIndex(where: { $0.id == notification.id }) else { return }
        let now = ISO8601DateFormatter().string(from: Date())
        notifications[index] = AppNotification(
            id: notification.id, type: notification.type, title: notification.title,
            body: notification.body, createdAt: notification.createdAt, readAt: now
        )
        Task { await account.markNotificationRead(id: notification.id) }
    }

    private func markAllRead() {
        let now = ISO8601DateFormatter().string(from: Date())
        notifications = notifications.map { n in
            AppNotification(id: n.id, type: n.type, title: n.title, body: n.body, createdAt: n.createdAt, readAt: n.readAt ?? now)
        }
        Task { await account.markAllNotificationsRead() }
    }

    private func relativeDate(_ iso: String?) -> String? {
        guard let iso else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var date = formatter.date(from: iso)
        if date == nil {
            formatter.formatOptions = [.withInternetDateTime]
            date = formatter.date(from: iso)
        }
        guard let date else { return nil }
        let relative = RelativeDateTimeFormatter()
        relative.unitsStyle = .abbreviated
        return relative.localizedString(for: date, relativeTo: Date())
    }
}
