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
                    .shadow(color: AppTheme.dynamicAccent.opacity(0.5), radius: 24, x: 0, y: 8)
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
                                            colors: [AppTheme.dynamicAccent, AppTheme.accentSoft],
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
                        .shadow(color: AppTheme.dynamicAccent.opacity(0.4), radius: 8, x: 0, y: 4)
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

                // Library stats strip — turns the loading screen from a static spinner
                // into a quick "here's what's about to load" preview. Pulls straight from
                // already-in-memory `library` state (no network round-trip), so it's free
                // to show immediately and never adds to launch latency.
                statsStrip
                    .opacity(contentOpacity)

                Spacer()

                VStack(spacing: 8) {
                    // Determinate progress while `scanMediaLibrary` is actively
                    // converting items — turns "is this stuck?" into visible,
                    // ticking proof that the scan is moving, which matters most
                    // for big libraries where the indeterminate spinner used to
                    // sit there for many seconds with zero feedback.
                    if let progress = library.scanProgress, progress.total > 0 {
                        ProgressView(value: Double(progress.current), total: Double(progress.total))
                            .tint(AppTheme.dynamicAccent)
                            .frame(maxWidth: 180)
                        Text("Scanning \(progress.current) of \(progress.total) songs\u{2026}")
                            .font(.caption)
                            .foregroundStyle(AppTheme.textSecondary)
                            .contentTransition(.numericText())
                            .animation(.easeOut(duration: 0.2), value: progress.current)
                    } else {
                        ProgressView()
                            .tint(AppTheme.dynamicAccent)
                        Text("Loading library\u{2026}")
                            .font(.caption)
                            .foregroundStyle(AppTheme.textSecondary)
                    }
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
                                .background(AppTheme.dynamicAccent, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
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
                // Was a flat 300ms delay regardless of whether the account/avatar
                // were already available (they usually are, restored synchronously
                // in AccountService.init from local storage/cache) — that made the
                // "Hello! @username" greeting feel like it loaded late. Show it
                // immediately when we already have the user; otherwise keep a short
                // delay so the fade-in doesn't pop in mid-logo-animation.
                let delay: UInt64 = (account.isLoggedIn && account.currentUser != nil) ? 0 : 300_000_000
                if delay > 0 { try? await Task.sleep(nanoseconds: delay) }
                withAnimation(.easeIn(duration: 0.3)) { contentOpacity = 1.0 }
            }
            Task {
                // Previously a flat 1.5s timer — for small/cached libraries that's plenty,
                // but for big ones (1000+ songs imported from Apple Music) the media-library
                // scan is still running long after this fires: the user lands in a library
                // that's still populating mid-interaction (rows reflowing, artwork popping
                // in, the mini player jumping between tracks) — exactly the "freakout" feel
                // reported after large imports/updates. Now we hold here until
                // `library.isScanning` (set by scanMediaLibrary/requestAccessAndScan, the
                // dominant scan path for big libraries — see LibraryView.onAppear) drops
                // back to false, so the user never sees the library mid-rebuild.
                //
                // Two safety rails: a minimum hold so the screen doesn't just flicker for
                // small libraries (and so we're not sampling `isScanning` in the brief gap
                // before LibraryView.onAppear has actually flipped it true), and a maximum
                // cap so a stuck/never-starting scan can never trap the user here.
                let minimumHold: UInt64 = 1_200_000_000   //  1.2 s
                let maximumHold: UInt64 = 15_000_000_000  // 15.0 s
                let pollInterval: UInt64 = 250_000_000    //  0.25 s

                try? await Task.sleep(nanoseconds: minimumHold)
                var waited = minimumHold
                while await MainActor.run(body: { library.isScanning }), waited < maximumHold {
                    try? await Task.sleep(nanoseconds: pollInterval)
                    waited += pollInterval
                }

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

    // MARK: - Stats strip

    private var statsStrip: some View {
        HStack(spacing: 10) {
            LaunchStatChip(icon: "music.note", value: "\(library.allSongs.count)", label: "Songs")
            LaunchStatChip(icon: "music.mic", value: "\(library.artists.count)", label: "Artists")
            LaunchStatChip(icon: "music.note.list", value: "\(library.playlists.count)", label: "Playlists")
            LaunchStatChip(icon: "clock.fill", value: totalLibraryDuration, label: "Listening")
        }
        .padding(.horizontal, 28)
    }

    /// Sum of every song's duration, formatted like QueueView's "Xh Ym" footer total.
    private var totalLibraryDuration: String {
        let seconds = library.allSongs.reduce(0) { $0 + $1.duration }
        guard seconds.isFinite, seconds > 0 else { return "0m" }
        let total = Int(seconds.rounded())
        let h = total / 3600
        let m = (total % 3600) / 60
        return h > 0 ? "\(h)h \(m)m" : "\(m)m"
    }
}

// MARK: - LaunchStatChip

private struct LaunchStatChip: View {
    let icon: String
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(AppTheme.dynamicAccent)
            Text(value)
                .font(AppTheme.monoFont(size: 15).weight(.semibold))
                .foregroundStyle(AppTheme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(AppTheme.bodyFont(size: 11))
                .foregroundStyle(AppTheme.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(AppTheme.surface.opacity(0.6), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
