import SwiftUI

// MARK: - LaunchView

struct LaunchView: View {
    @EnvironmentObject private var account: AccountService
    @EnvironmentObject private var library: LibraryManager
    @Binding var isLoading: Bool

    @State private var showNewUserPrompt = false
    @State private var logoScale: CGFloat = 0.6
    @State private var logoOpacity: Double = 0
    @State private var contentOpacity: Double = 0

    var body: some View {
        ZStack {
            AppTheme.background.ignoresSafeArea()

            VStack(spacing: 24) {
                Spacer()

                // App logo — styled accent tile with music note
                ZStack {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [AppTheme.accent, AppTheme.accentSoft],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    Image(systemName: "music.note.list")
                        .font(.system(size: 48, weight: .bold))
                        .foregroundStyle(.white)
                }
                .frame(width: 110, height: 110)
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                .shadow(color: AppTheme.accent.opacity(0.5), radius: 24, x: 0, y: 8)
                .scaleEffect(logoScale)
                .opacity(logoOpacity)

                if account.isLoggedIn, let user = account.currentUser {
                    // Logged in — personalised greeting
                    VStack(spacing: 8) {
                        // Profile avatar — real image or initials fallback
                        ZStack {
                            if let img = account.avatarImage {
                                Image(uiImage: img)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 70, height: 70)
                                    .clipShape(Circle())
                            } else {
                                Circle()
                                    .fill(
                                        LinearGradient(
                                            colors: [AppTheme.accent, AppTheme.accentSoft],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                    .frame(width: 70, height: 70)
                                Text(String((user.displayName ?? user.username).prefix(1)).uppercased())
                                    .font(.title.bold())
                                    .foregroundStyle(.white)
                            }
                        }
                        .shadow(color: AppTheme.accent.opacity(0.4), radius: 8, x: 0, y: 4)
                        Text("Hello! @\(user.username)")
                            .font(.title2.bold())
                            .foregroundStyle(AppTheme.textPrimary)
                        if let name = user.displayName, !name.isEmpty {
                            Text(name)
                                .font(.subheadline)
                                .foregroundStyle(AppTheme.textSecondary)
                        }
                    }
                    .opacity(contentOpacity)
                } else {
                    // Not logged in
                    VStack(spacing: 8) {
                        Text("StashOpusPlayer")
                            .font(.title.bold())
                            .foregroundStyle(AppTheme.textPrimary)
                        Text("Your music, your way")
                            .font(.subheadline)
                            .foregroundStyle(AppTheme.textSecondary)
                    }
                    .opacity(contentOpacity)
                }

                Spacer()

                // Loading indicator at bottom
                VStack(spacing: 8) {
                    ProgressView()
                        .tint(AppTheme.accent)
                    Text("Loading library\u{2026}")
                        .font(.caption)
                        .foregroundStyle(AppTheme.textSecondary)
                }
                .opacity(contentOpacity)
                .padding(.bottom, 40)
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.7)) {
                logoScale = 1.0
                logoOpacity = 1.0
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                withAnimation(.easeIn(duration: 0.4)) {
                    contentOpacity = 1.0
                }
            }
            // Auto-dismiss after minimum 1.5 seconds once library is loading
            Task {
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                await MainActor.run {
                    if !account.isLoggedIn {
                        showNewUserPrompt = true
                    } else {
                        withAnimation(.easeOut(duration: 0.5)) {
                            isLoading = false
                        }
                    }
                }
            }
        }
        .alert("Create an Account?", isPresented: $showNewUserPrompt) {
            Button("Create Account") {
                withAnimation(.easeOut(duration: 0.5)) {
                    isLoading = false
                }
            }
            Button("Skip for Now", role: .cancel) {
                withAnimation(.easeOut(duration: 0.5)) {
                    isLoading = false
                }
            }
        } message: {
            Text("Without an account, your playlists and settings won't be saved to the cloud. If you delete the app, your data will be lost!")
        }
    }
}
