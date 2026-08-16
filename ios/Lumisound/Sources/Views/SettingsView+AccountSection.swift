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
        } header: {
            sectionHeader("Account", icon: "person.crop.circle.fill", tint: .blue)
        }
        .listRowBackground(tintedRowBackground(.blue))
    }
}
