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

    // Gentle breathing pulse on the app icon while the launch screen is visible.
    @State private var logoBreathing = false
    // Animated chrome: drifting aurora backdrop + rotating glow ring.
    @State private var ringRotation: Double = 0
    @State private var auroraShift = false

    var body: some View {
        ZStack {
            // Animated ambient backdrop — drifting accent-colored aurora blobs
            // over the base background, giving the launch screen depth/motion.
            LaunchAuroraBackground(animate: auroraShift)

            VStack(spacing: 24) {
                Spacer()

                // App icon framed by a rotating gradient halo + live equalizer
                // bars — a musical, animated centerpiece instead of a static icon.
                ZStack {
                    Circle()
                        .stroke(
                            AngularGradient(
                                colors: [AppTheme.dynamicAccent, AppTheme.accentSoft, AppTheme.dynamicAccent],
                                center: .center
                            ),
                            lineWidth: 3
                        )
                        .frame(width: 150, height: 150)
                        .blur(radius: 1)
                        .rotationEffect(.degrees(ringRotation))
                        .opacity(logoOpacity)

                    Circle()
                        .fill(AppTheme.dynamicAccent)
                        .frame(width: 150, height: 150)
                        .blur(radius: 40)
                        .opacity(logoOpacity * (logoBreathing ? 0.5 : 0.3))

                    Image("AppIconDisplay")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 110, height: 110)
                        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 24, style: .continuous)
                                .stroke(.white.opacity(0.15), lineWidth: 1)
                        )
                        .shadow(color: AppTheme.dynamicAccent.opacity(0.5), radius: 24, x: 0, y: 8)
                        .scaleEffect(logoScale * (logoBreathing ? 1.03 : 1.0))
                        .opacity(logoOpacity)
                }

                // Live equalizer bars under the icon (animate while the screen is up).
                LaunchEqualizerBars(animate: logoBreathing)
                    .frame(height: 22)
                    .opacity(contentOpacity)

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
                            .font(.system(size: 34, weight: .bold, design: .rounded))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [AppTheme.textPrimary, AppTheme.dynamicAccent],
                                    startPoint: .leading, endPoint: .trailing
                                )
                            )
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
            // Continuous rotating halo + drifting aurora for as long as the
            // launch screen is visible.
            withAnimation(.linear(duration: 14).repeatForever(autoreverses: false)) {
                ringRotation = 360
            }
            withAnimation(.easeInOut(duration: 6).repeatForever(autoreverses: true)) {
                auroraShift = true
            }
            // Start a subtle breathing pulse on the icon once the entrance
            // spring has settled, for as long as the launch screen is up.
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 600_000_000)
                withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) {
                    logoBreathing = true
                }
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

// MARK: - LaunchAuroraBackground

/// Drifting, heavily-blurred accent blobs over the base background — gives the
/// launch screen subtle ambient motion without any artwork dependency.
private struct LaunchAuroraBackground: View {
    let animate: Bool

    var body: some View {
        ZStack {
            AppTheme.background.ignoresSafeArea()

            Circle()
                .fill(AppTheme.dynamicAccent)
                .frame(width: 320, height: 320)
                .blur(radius: 90)
                .opacity(0.35)
                .offset(x: animate ? -90 : -40, y: animate ? -180 : -120)

            Circle()
                .fill(AppTheme.accentSoft)
                .frame(width: 280, height: 280)
                .blur(radius: 90)
                .opacity(0.30)
                .offset(x: animate ? 110 : 60, y: animate ? 200 : 150)

            Circle()
                .fill(AppTheme.dynamicAccent.opacity(0.8))
                .frame(width: 220, height: 220)
                .blur(radius: 80)
                .opacity(0.22)
                .offset(x: animate ? 80 : 30, y: animate ? -60 : -20)
        }
        .ignoresSafeArea()
    }
}

// MARK: - LaunchEqualizerBars

/// A small row of animated equalizer bars — a musical loading flourish. Each
/// bar bounces on its own offset sine while `animate` is true.
private struct LaunchEqualizerBars: View {
    let animate: Bool
    private let barCount = 7

    var body: some View {
        TimelineView(.animation(paused: !animate)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            HStack(spacing: 5) {
                ForEach(0..<barCount, id: \.self) { i in
                    let phase = Double(i) * 0.7
                    let h = animate ? (0.35 + 0.65 * (0.5 + 0.5 * sin(t * 4 + phase))) : 0.4
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [AppTheme.dynamicAccent, AppTheme.accentSoft],
                                startPoint: .bottom, endPoint: .top
                            )
                        )
                        .frame(width: 4, height: 22 * CGFloat(h))
                }
            }
            .frame(height: 22, alignment: .center)
        }
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
        .adaptiveGlass(
            in: RoundedRectangle(cornerRadius: 14, style: .continuous),
            fallback: AppTheme.surface.opacity(0.6)
        )
    }
}
