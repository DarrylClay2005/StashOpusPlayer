import SwiftUI
import UIKit

// MARK: - SettingsView Notifications Entry Point

extension SettingsView {

    // MARK: — Notifications Section

    var notificationsSection: some View {
        Section {
            NavigationLink(destination: NotificationsSettingsView()) {
                HStack {
                    Label("Notifications", systemImage: "bell.badge")
                        .foregroundStyle(AppTheme.textPrimary)
                    Spacer()
                    notificationsStatusPill
                }
            }
        } header: {
            sectionHeader("Notifications", icon: "bell.badge.fill", tint: .orange)
        }
        .listRowBackground(AppTheme.surface)
        .animation(.easeInOut(duration: 0.2), value: notificationService.isEnabled)
        .animation(.easeInOut(duration: 0.2), value: notificationService.isAuthorized)
    }

    @ViewBuilder
    private var notificationsStatusPill: some View {
        if !notificationService.isEnabled {
            statusPill(text: "Off", color: AppTheme.textSecondary)
        } else if !notificationService.isAuthorized {
            statusPill(text: "Needs Access", color: AppTheme.warning)
        } else {
            statusPill(text: "On", color: AppTheme.success)
        }
    }

    private func statusPill(text: String, color: Color) -> some View {
        Text(text)
            .font(AppTheme.bodyFont(size: 12))
            .foregroundStyle(color)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(color.opacity(0.15), in: Capsule())
    }
}

// MARK: - NotificationsSettingsView
//
// Dedicated Settings screen: OS authorization status (with a deep link to
// iOS Settings when denied), the master on/off switch, and a per-topic
// preference toggle for every registered `NotificationTopic` — grouped by
// `NotificationTopicGroup`, each group collapsible for a lighter-feeling list
// once more topics accumulate (e.g. once the social workstream registers its
// own friend-activity topics under `.social`).

struct NotificationsSettingsView: View {
    @ObservedObject private var service = NotificationService.shared

    /// Every group starts expanded; collapsing is purely a display
    /// convenience so a long list of topics (as more get registered over
    /// time) doesn't force a wall of toggles on first open.
    @State private var collapsedGroups: Set<NotificationTopicGroup> = []

    var body: some View {
        List {
            statusSection
            masterToggleSection

            ForEach(NotificationTopicRegistry.grouped, id: \.group) { entry in
                topicGroupSection(entry.group, entry.topics)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(GalleryBackgroundView().ignoresSafeArea())
        .navigationTitle("Notifications")
        .navigationBarTitleDisplayMode(.large)
        .task {
            // Re-checks (never re-prompts once determined) so the status
            // card is accurate the moment this screen opens, even if the
            // user just came back from granting access in iOS Settings.
            await service.requestAuthorization()
        }
    }

    // MARK: Status

    private var statusSection: some View {
        Section {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: statusIcon)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(statusColor)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 3) {
                    Text(statusTitle)
                        .font(AppTheme.headlineFont(size: 15))
                        .foregroundStyle(AppTheme.textPrimary)
                    Text(statusDetail)
                        .font(AppTheme.bodyFont(size: 12))
                        .foregroundStyle(AppTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 4)
            .animation(.easeInOut(duration: 0.2), value: statusTitle)

            if service.isEnabled && !service.isAuthorized {
                Button {
                    openSystemSettings()
                } label: {
                    Label("Open iOS Settings", systemImage: "gearshape")
                        .foregroundStyle(AppTheme.dynamicAccent)
                }
            }

            if let error = service.lastAuthorizationError {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(AppTheme.bodyFont(size: 12))
                    .foregroundStyle(AppTheme.warning)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .listRowBackground(AppTheme.surface)
    }

    private var statusIcon: String {
        guard service.isEnabled else { return "bell.slash" }
        return service.isAuthorized ? "bell.badge.fill" : "bell.slash.fill"
    }

    private var statusColor: Color {
        guard service.isEnabled else { return AppTheme.textSecondary }
        return service.isAuthorized ? AppTheme.success : AppTheme.warning
    }

    private var statusTitle: String {
        guard service.isEnabled else { return "Notifications Off" }
        return service.isAuthorized ? "Notifications Active" : "Permission Needed"
    }

    private var statusDetail: String {
        guard service.isEnabled else {
            return "Turn on Device Notifications below to receive alerts."
        }
        return service.isAuthorized
            ? "Lumisound can alert you in the background and while the app is open."
            : "Notifications are turned off in iOS Settings for Lumisound. Enable them there to receive any of the alerts below."
    }

    private func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    // MARK: Master toggle

    private var masterToggleSection: some View {
        Section {
            Toggle(isOn: $service.isEnabled) {
                Label("Device Notifications", systemImage: "bell.badge")
                    .foregroundStyle(AppTheme.textPrimary)
            }
            .tint(AppTheme.dynamicAccent)
        } footer: {
            Text("Master switch for every notification type below. Turning this off silences all of them, regardless of their individual toggle — turn it back on to restore whatever you had enabled per category.")
                .font(AppTheme.bodyFont(size: 12))
                .foregroundStyle(AppTheme.textSecondary)
        }
        .listRowBackground(AppTheme.surface)
    }

    // MARK: Per-topic groups (collapsible)

    @ViewBuilder
    private func topicGroupSection(_ group: NotificationTopicGroup, _ topics: [NotificationTopic]) -> some View {
        let isCollapsed = collapsedGroups.contains(group)
        Section {
            if !isCollapsed {
                ForEach(topics) { topic in
                    topicRow(topic)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        } header: {
            Button {
                withAnimation(.easeInOut(duration: 0.22)) {
                    if isCollapsed {
                        collapsedGroups.remove(group)
                    } else {
                        collapsedGroups.insert(group)
                    }
                }
            } label: {
                HStack {
                    Label(group.displayName.uppercased(), systemImage: group.icon)
                        .font(AppTheme.bodyFont(size: 11))
                        .foregroundStyle(AppTheme.textSecondary)
                        .kerning(0.8)
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(AppTheme.textSecondary)
                        .rotationEffect(.degrees(isCollapsed ? -90 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .listRowBackground(AppTheme.surface)
        .animation(.easeInOut(duration: 0.22), value: isCollapsed)
    }

    private func topicRow(_ topic: NotificationTopic) -> some View {
        Toggle(isOn: Binding(
            get: { service.isTopicEnabled(topic.id) },
            set: { service.setTopicEnabled($0, for: topic.id) }
        )) {
            VStack(alignment: .leading, spacing: 3) {
                Label(topic.displayName, systemImage: topic.icon)
                    .foregroundStyle(AppTheme.textPrimary)
                Text(topic.detail)
                    .font(AppTheme.bodyFont(size: 12))
                    .foregroundStyle(AppTheme.textSecondary)
                    .padding(.leading, 28)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .tint(AppTheme.dynamicAccent)
        .disabled(!service.isEnabled)
        .opacity(service.isEnabled ? 1 : 0.5)
        .animation(.easeInOut(duration: 0.18), value: service.isEnabled)
    }
}
