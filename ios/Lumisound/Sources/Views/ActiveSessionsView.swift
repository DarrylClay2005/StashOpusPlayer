import SwiftUI

// MARK: - ActiveSessionsView
//
// Shows every active login (device/session) for this account, from
// GET /auth/sessions, and lets the user sign out individual devices via
// DELETE /auth/sessions/{token_id}.

struct ActiveSessionsView: View {
    @EnvironmentObject private var account: AccountService

    @State private var pendingRevoke: AccountSession?

    var body: some View {
        List {
            if account.sessions.isEmpty {
                Text("No active sessions found.")
                    .font(AppTheme.bodyFont(size: 13))
                    .foregroundStyle(AppTheme.textSecondary)
                    .listRowBackground(AppTheme.surface)
            } else {
                Section {
                    ForEach(account.sessions) { session in
                        Button {
                            pendingRevoke = session
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 3) {
                                    HStack(spacing: 6) {
                                        Text(session.deviceName ?? "Unknown device")
                                            .font(AppTheme.bodyFont(size: 14))
                                            .foregroundStyle(AppTheme.textPrimary)
                                        if session.isCurrent {
                                            Text("This Device")
                                                .font(.caption2.weight(.semibold))
                                                .foregroundStyle(AppTheme.dynamicAccent)
                                                .padding(.horizontal, 6)
                                                .padding(.vertical, 2)
                                                .background(AppTheme.dynamicAccent.opacity(0.15), in: Capsule())
                                        }
                                    }
                                    if let date = session.createdDate {
                                        Text("Signed in \(date.formatted(.relative(presentation: .named)))")
                                            .font(AppTheme.bodyFont(size: 12))
                                            .foregroundStyle(AppTheme.textSecondary)
                                    }
                                }
                                Spacer()
                                Image(systemName: "rectangle.portrait.and.arrow.right")
                                    .foregroundStyle(AppTheme.error)
                            }
                        }
                        .disabled(account.isSyncing)
                    }
                } footer: {
                    Text("Tap a session to sign it out. Signing out the current device signs you out of Lumisound on this phone.")
                        .font(AppTheme.bodyFont(size: 12))
                        .foregroundStyle(AppTheme.textSecondary)
                }
                .listRowBackground(AppTheme.surface)
            }
        }
        .scrollContentBackground(.hidden)
        .background(GalleryBackgroundView().ignoresSafeArea())
        .navigationTitle("Active Sessions")
        .navigationBarTitleDisplayMode(.inline)
        .task { await account.fetchSessions() }
        .refreshable { await account.fetchSessions() }
        .confirmationDialog(
            "Sign out this device?",
            isPresented: Binding(
                get: { pendingRevoke != nil },
                set: { if !$0 { pendingRevoke = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Sign Out", role: .destructive) {
                guard let session = pendingRevoke else { return }
                pendingRevoke = nil
                Task { await account.revokeSession(tokenId: session.tokenId) }
            }
            Button("Cancel", role: .cancel) { pendingRevoke = nil }
        } message: {
            if let session = pendingRevoke, session.isCurrent {
                Text("This will sign you out of Lumisound on this device.")
            } else {
                Text("That device will need to sign in again to use Lumisound.")
            }
        }
    }
}
