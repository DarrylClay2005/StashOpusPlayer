import SwiftUI

// MARK: - Round 4: Active Sessions + Notifications
//
// Both are plain bridge REST (GET /auth/sessions, GET /user/notifications) —
// see the round-4 scope note in TVBridge.swift for what was deliberately
// left out (push registration, change-password/2FA/delete-account, the
// full friend-request flow, Listen Together).

/// Parses the bridge's ISO-8601 timestamps (with fractional seconds) into a
/// short relative-ish string. Falls back to the raw string if parsing fails
/// rather than showing nothing.
private func tvFormattedTimestamp(_ iso: String?) -> String {
    guard let iso else { return "" }
    let withFraction = ISO8601DateFormatter()
    withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    let withoutFraction = ISO8601DateFormatter()
    withoutFraction.formatOptions = [.withInternetDateTime]
    guard let date = withFraction.date(from: iso) ?? withoutFraction.date(from: iso) else { return iso }

    let formatter = RelativeDateTimeFormatter()
    formatter.unitsStyle = .short
    return formatter.localizedString(for: date, relativeTo: Date())
}

// MARK: - Active Sessions

struct TVSessionsView: View {
    @ObservedObject var client: TVBridgeClient
    @ObservedObject var account: TVAccount
    let token: String

    var body: some View {
        List {
            if client.isLoadingSessions && client.sessions.isEmpty {
                HStack { Spacer(); ProgressView(); Spacer() }
            } else if client.sessions.isEmpty {
                Text("No active sessions.").foregroundStyle(.secondary)
            } else {
                ForEach(client.sessions) { session in
                    sessionRow(session)
                }
            }
        }
        .navigationTitle("Active Sessions")
        .task {
            if client.sessions.isEmpty { await client.fetchSessions(token: token) }
        }
    }

    private func sessionRow(_ session: TVSession) -> some View {
        HStack(spacing: 20) {
            Image(systemName: session.isCurrent ? "appletv.fill" : "iphone")
                .font(.title2)
                .foregroundStyle(session.isCurrent ? Color.accentColor : Color.secondary)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 10) {
                    Text(session.deviceName ?? "Unknown Device").font(.headline)
                    if session.isCurrent {
                        Text("This Device")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(Color.accentColor.opacity(0.2), in: Capsule())
                    }
                }
                Text("Signed in \(tvFormattedTimestamp(session.createdAt))")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button(role: .destructive) {
                Task {
                    let wasCurrentSession = await client.revokeSession(session.tokenID, token: token)
                    if wasCurrentSession { account.logout() }
                }
            } label: {
                Text("Revoke")
            }
        }
    }
}

// MARK: - Notifications

struct TVNotificationsView: View {
    @ObservedObject var client: TVBridgeClient
    let token: String

    var body: some View {
        List {
            if client.notifications.contains(where: \.isUnread) {
                Button("Mark All Read") {
                    Task { await client.markAllNotificationsRead(token: token) }
                }
            }
            if client.isLoadingNotifications && client.notifications.isEmpty {
                HStack { Spacer(); ProgressView(); Spacer() }
            } else if client.notifications.isEmpty {
                Text("No notifications yet.").foregroundStyle(.secondary)
            } else {
                ForEach(client.notifications) { note in
                    Button {
                        guard note.isUnread else { return }
                        Task { await client.markNotificationRead(note.id, token: token) }
                    } label: {
                        notificationRow(note)
                    }
                }
            }
        }
        .navigationTitle("Notifications")
        .task {
            if client.notifications.isEmpty { await client.fetchNotifications(token: token) }
        }
    }

    private func notificationRow(_ note: TVNotification) -> some View {
        HStack(alignment: .top, spacing: 16) {
            Circle()
                .fill(note.isUnread ? Color.accentColor : Color.clear)
                .frame(width: 10, height: 10)
                .padding(.top, 6)
            VStack(alignment: .leading, spacing: 4) {
                Text(note.title ?? "Notification").font(.headline)
                if let body = note.body, !body.isEmpty {
                    Text(body).font(.subheadline).foregroundStyle(.secondary)
                }
                Text(tvFormattedTimestamp(note.createdAt))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
    }
}

// MARK: - Friends Listening Now
//
// Deliberately minimal — a passive "who's playing something right now" card,
// not a full friends/social tab (no add/accept/decline, no browsing other
// profiles). A shared living-room screen showing a whole social graph is a
// worse fit than on a personal phone; this only ever renders when it has
// something to show (see TVBridgeClient.fetchFriendsListening).

struct TVFriendsListeningCard: View {
    let friendsListening: [TVFriendListening]

    var body: some View {
        if !friendsListening.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                Text("Friends Listening Now").font(.title3.weight(.semibold))
                VStack(spacing: 0) {
                    ForEach(friendsListening) { entry in
                        HStack(spacing: 16) {
                            Image(systemName: "person.crop.circle.fill")
                                .font(.title2)
                                .foregroundStyle(.secondary)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(entry.friend.name).font(.subheadline.weight(.semibold))
                                if let title = entry.presence.nowPlayingTitle, !title.isEmpty {
                                    Text("\(title)\(entry.presence.nowPlayingArtist.map { " — \($0)" } ?? "")")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                            }
                            Spacer()
                            Image(systemName: "waveform")
                                .foregroundStyle(Color.accentColor)
                        }
                        .padding(.vertical, 8)
                    }
                }
            }
        }
    }
}
