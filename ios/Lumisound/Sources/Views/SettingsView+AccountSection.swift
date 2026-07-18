import MediaPlayer
import SwiftUI

extension SettingsView {

    // MARK: — Account Section

    var accountSection: some View {
        Section {
            if account.isLoggedIn, let user = account.currentUser {
                NavigationLink(destination: AccountView()
                    .environmentObject(account)
                    .environmentObject(library)
                ) {
                    HStack(spacing: 12) {
                        // Avatar: real image or initials fallback
                        ZStack {
                            if let img = account.avatarImage {
                                Image(uiImage: img)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 40, height: 40)
                                    .clipShape(Circle())
                            } else {
                                Circle()
                                    .fill(
                                        LinearGradient(
                                            colors: [AppTheme.dynamicAccent, AppTheme.accentSoft],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                    .frame(width: 40, height: 40)
                                Text(String((user.displayName ?? user.username).prefix(1)).uppercased())
                                    .font(.title3.bold())
                                    .foregroundStyle(.white)
                            }
                        }
                        .shadow(color: AppTheme.dynamicAccent.opacity(0.3), radius: 4, x: 0, y: 2)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(user.displayName ?? user.username)
                                .fontWeight(.medium)
                                .foregroundStyle(AppTheme.textPrimary)
                            Text("Tap to manage account")
                                .font(.caption)
                                .foregroundStyle(AppTheme.textSecondary)
                        }
                    }
                }
            } else {
                Button { showLogin = true } label: {
                    Label("Sign In / Create Account", systemImage: "person.badge.plus")
                        .foregroundStyle(AppTheme.dynamicAccent)
                }
            }

            // Placeholder entry point for the social-ecosystem workstream's
            // profile/accent-color/friends settings (developed on its own
            // branch in parallel with this redesign). Kept behind
            // `isLoggedIn` like the rest of this section, styled to match,
            // and pointed at a local stub view so Settings has an obvious,
            // already-laid-out slot for that work to land in without needing
            // its own follow-up restructuring of this section.
            if account.isLoggedIn {
                NavigationLink(destination: SocialProfilePlaceholderView()) {
                    Label("Profile & Social", systemImage: "person.2.circle")
                        .foregroundStyle(AppTheme.textPrimary)
                }
            }
        } header: {
            sectionHeader("Account")
        }
        .listRowBackground(AppTheme.surface)
    }
}

// MARK: - SocialProfilePlaceholderView
//
// STUB — intentionally minimal. The social-ecosystem workstream owns
// profile customization, accent-color-as-identity, and friends/followers,
// and is expected to either replace this view's body outright or add its
// own destinations alongside it. This exists purely so `SettingsView`'s
// Account section already has a stable, styled `NavigationLink` slot for
// that work, instead of the social branch needing to touch
// SettingsView+AccountSection.swift (owned by this workstream) to add one.
private struct SocialProfilePlaceholderView: View {
    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Coming Soon", systemImage: "hammer")
                        .font(AppTheme.headlineFont(size: 15))
                        .foregroundStyle(AppTheme.textPrimary)
                    Text("Profile customization, accent-color-as-identity, and friends/followers settings will appear here once that work lands.")
                        .font(AppTheme.bodyFont(size: 13))
                        .foregroundStyle(AppTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 6)
            }
            .listRowBackground(AppTheme.surface)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(GalleryBackgroundView().ignoresSafeArea())
        .navigationTitle("Profile & Social")
        .navigationBarTitleDisplayMode(.inline)
    }
}
