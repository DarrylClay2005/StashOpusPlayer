import SwiftUI

// MARK: - FriendRequestsView
//
// Incoming (accept/decline) and outgoing (cancel) pending friend requests.
// Pushed from FriendsListView; also reachable via the badge count on
// AccountView's "Friends" row.
struct FriendRequestsView: View {
    @EnvironmentObject private var social: SocialService
    @State private var actingOn: Set<String> = []

    var body: some View {
        List {
            Section {
                if social.incomingRequests.isEmpty {
                    Text("No incoming requests.")
                        .foregroundStyle(AppTheme.textSecondary)
                        .font(AppTheme.bodyFont(size: 13))
                } else {
                    ForEach(social.incomingRequests) { request in
                        HStack(spacing: 12) {
                            NavigationLink(destination: PublicProfileView(userId: request.userId)) {
                                requestRow(request)
                            }
                            .buttonStyle(.plain)

                            if actingOn.contains(request.id) {
                                ProgressView().tint(AppTheme.dynamicAccent)
                            } else {
                                Button {
                                    act(request.id) { await social.acceptRequest(request.id) }
                                } label: {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(AppTheme.success)
                                }
                                .buttonStyle(.plain)

                                Button {
                                    act(request.id) { await social.declineRequest(request.id) }
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundStyle(AppTheme.error)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            } header: {
                sectionHeader("Incoming")
            }
            .listRowBackground(AppTheme.surface)

            Section {
                if social.outgoingRequests.isEmpty {
                    Text("No outgoing requests.")
                        .foregroundStyle(AppTheme.textSecondary)
                        .font(AppTheme.bodyFont(size: 13))
                } else {
                    ForEach(social.outgoingRequests) { request in
                        HStack(spacing: 12) {
                            NavigationLink(destination: PublicProfileView(userId: request.userId)) {
                                requestRow(request)
                            }
                            .buttonStyle(.plain)

                            if actingOn.contains(request.id) {
                                ProgressView().tint(AppTheme.dynamicAccent)
                            } else {
                                Button("Cancel") {
                                    act(request.id) { await social.cancelRequest(request.id) }
                                }
                                .font(AppTheme.bodyFont(size: 13))
                                .foregroundStyle(AppTheme.textSecondary)
                            }
                        }
                    }
                }
            } header: {
                sectionHeader("Outgoing")
            }
            .listRowBackground(AppTheme.surface)
        }
        .scrollContentBackground(.hidden)
        .navigationTitle("Friend Requests")
        .navigationBarTitleDisplayMode(.inline)
        .task { await social.fetchFriendRequests() }
        .refreshable { await social.fetchFriendRequests() }
    }

    private func requestRow(_ request: SocialFriendRequest) -> some View {
        HStack(spacing: 12) {
            SocialAvatarView(userId: request.userId, size: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(request.displayName ?? request.username)
                    .foregroundStyle(AppTheme.textPrimary)
                Text("@\(request.username)")
                    .font(AppTheme.bodyFont(size: 12))
                    .foregroundStyle(AppTheme.textSecondary)
            }
        }
    }

    private func act(_ id: String, _ operation: @escaping () async -> Void) {
        guard !actingOn.contains(id) else { return }
        actingOn.insert(id)
        Task {
            defer { actingOn.remove(id) }
            await operation()
        }
    }

    private func sectionHeader(_ text: String) -> some View {
        Text(text.uppercased())
            .font(AppTheme.bodyFont(size: 11))
            .foregroundStyle(AppTheme.textSecondary)
            .kerning(0.8)
    }
}
