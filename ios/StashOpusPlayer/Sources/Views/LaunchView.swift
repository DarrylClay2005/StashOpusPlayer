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

                // App icon / logo
                Group {
                    if let uiImage = UIImage(named: "AppIcon") {
                        Image(uiImage: uiImage)
                            .resizable()
                    } else {
                        // Fallback: accent-colored rounded square with music note
                        ZStack {
                            RoundedRectangle(cornerRadius: 22, style: .continuous)
                                .fill(AppTheme.accent)
                            Image(systemName: "music.note")
                                .font(.system(size: 50, weight: .bold))
                                .foregroundStyle(.white)
                        }
                    }
                }
                .scaledToFit()
                .frame(width: 100, height: 100)
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                .shadow(color: AppTheme.accent.opacity(0.4), radius: 20)
                .scaleEffect(logoScale)
                .opacity(logoOpacity)

                if account.isLoggedIn, let user = account.currentUser {
                    // Logged in — personalised greeting
                    VStack(spacing: 8) {
                        // Profile avatar
                        ZStack {
                            Circle()
                                .fill(AppTheme.accent)
                                .frame(width: 70, height: 70)
                            Text(String(user.username.prefix(1)).uppercased())
                                .font(.title.bold())
                                .foregroundStyle(.white)
                        }
                        Text("Hello! @\(user.username)")
                            .font(.title2.bold())
                            .foregroundStyle(AppTheme.textPrimary)
                        if let name = user.displayName {
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
