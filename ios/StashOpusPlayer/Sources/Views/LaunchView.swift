import SwiftUI

// MARK: - LaunchView

struct LaunchView: View {
    @EnvironmentObject private var account: AccountService
    @EnvironmentObject private var library: LibraryManager
    @Binding var isLoading: Bool

    @State private var showPrompt = false
    @State private var showLoginSheet = false
    @State private var loginStartOnRegister = false

    @State private var logoScale: CGFloat = 0.6
    @State private var logoOpacity: Double = 0
    @State private var contentOpacity: Double = 0

    var body: some View {
        ZStack {
            AppTheme.background.ignoresSafeArea()

            VStack(spacing: 24) {
                Spacer()

                // App icon — uses the real Lumisound icon from Assets.xcassets
                Image("AppIconDisplay")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 110, height: 110)
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .shadow(color: AppTheme.accent.opacity(0.5), radius: 24, x: 0, y: 8)
                    .scaleEffect(logoScale)
                    .opacity(logoOpacity)

                if account.isLoggedIn, let user = account.currentUser {
                    VStack(spacing: 8) {
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
                    VStack(spacing: 8) {
                        Text("Lumisound")
                            .font(.title.bold())
                            .foregroundStyle(AppTheme.textPrimary)
                        Text("Your music, your way")
                            .font(.subheadline)
                            .foregroundStyle(AppTheme.textSecondary)
                    }
                    .opacity(contentOpacity)
                }

                Spacer()

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

            // Account prompt overlay — shown when not logged in after load
            if showPrompt && !account.isLoggedIn {
                Color.black.opacity(0.6).ignoresSafeArea()
                    .transition(.opacity)

                VStack(spacing: 0) {
                    Spacer()

                    VStack(spacing: 16) {
                        VStack(spacing: 6) {
                            Text("Welcome to Lumisound")
                                .font(.title2.bold())
                                .foregroundStyle(AppTheme.textPrimary)
                            Text("Create a free account to sync playlists, settings, and your personal library across devices.")
                                .font(.subheadline)
                                .foregroundStyle(AppTheme.textSecondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 8)
                        }

                        // Create Account
                        Button {
                            loginStartOnRegister = true
                            showLoginSheet = true
                        } label: {
                            Text("Create Account")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(AppTheme.accent, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                                .foregroundStyle(.white)
                        }
                        .buttonStyle(.plain)

                        // Log In
                        Button {
                            loginStartOnRegister = false
                            showLoginSheet = true
                        } label: {
                            Text("Log In")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(AppTheme.elevatedSurface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                                .foregroundStyle(AppTheme.textPrimary)
                        }
                        .buttonStyle(.plain)

                        // Skip
                        Button {
                            withAnimation(.easeOut(duration: 0.5)) {
                                showPrompt = false
                                isLoading = false
                            }
                        } label: {
                            Text("Continue without account")
                                .font(.subheadline)
                                .foregroundStyle(AppTheme.textSecondary)
                                .padding(.vertical, 6)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(24)
                    .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .padding(.horizontal, 20)
                    .padding(.bottom, 40)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.45, dampingFraction: 0.8), value: showPrompt)
        .sheet(isPresented: $showLoginSheet, onDismiss: {
            if account.isLoggedIn {
                withAnimation(.easeOut(duration: 0.5)) { isLoading = false }
            }
        }) {
            LoginView(startOnRegister: loginStartOnRegister)
                .environmentObject(account)
        }
        .onAppear {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.7)) {
                logoScale = 1.0
                logoOpacity = 1.0
            }
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 300_000_000)
                withAnimation(.easeIn(duration: 0.4)) { contentOpacity = 1.0 }
            }
            Task {
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                await MainActor.run {
                    if !account.isLoggedIn {
                        withAnimation { showPrompt = true }
                    } else {
                        withAnimation(.easeOut(duration: 0.5)) { isLoading = false }
                    }
                }
            }
        }
        // Auto-dismiss once login completes
        .onChange(of: account.isLoggedIn) { loggedIn in
            if loggedIn {
                showLoginSheet = false
                withAnimation(.easeOut(duration: 0.5)) { isLoading = false }
            }
        }
    }
}
