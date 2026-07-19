import AVFoundation
import SwiftUI
import UIKit

// MARK: - TabTransitionStyle

enum TabTransitionStyle: String, CaseIterable, Identifiable, Codable {
    case scalePop
    case slide
    case fadeOnly

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .scalePop: return "Scale Pop"
        case .slide:    return "Slide"
        case .fadeOnly: return "Fade Only"
        }
    }
}

struct ContentView: View {

    @EnvironmentObject private var player: AudioPlayerManager
    @EnvironmentObject private var streaming: StreamingService
    @EnvironmentObject private var account: AccountService
    @EnvironmentObject private var bridgeHealth: BridgeHealthService
    @ObservedObject private var toastCenter = ToastCenter.shared

    /// Persists the last-selected tab across launches.
    @AppStorage("selected_tab") private var selectedTab = 0
    @State private var showCarMode = false

    /// Drives a quick scale "pop" on the freshly-selected tab's content —
    /// dips slightly below 1.0 then springs back to 1.0 each time the tab changes.
    @State private var tabPopScale: CGFloat = 1.0
    /// Vertical dip used by the "Slide" transition style.
    @State private var tabSlideOffset: CGFloat = 0
    /// Opacity dip used by the "Slide" and "Fade Only" transition styles.
    @State private var tabContentOpacity: Double = 1.0
    @AppStorage("tab_transition_style") private var tabTransitionStyleRaw: String = TabTransitionStyle.scalePop.rawValue

    /// Set in Settings → Playback. When off, the floating Car Mode button is
    /// hidden and connecting to a car stereo no longer auto-presents it.
    @AppStorage("carModeEnabled") private var carModeEnabled: Bool = false

    /// Circular-cropped tab-bar-sized rendering of the user's avatar, shown in place
    /// of the gearshape Settings icon when logged in. Cached in @State (recomputed only
    /// when the avatar actually changes via onReceive below) rather than rendered inline
    /// in `body` — `ContentView` re-evaluates on every `player` publish (including
    /// position updates ~4×/sec during playback), and redrawing a UIGraphicsImageRenderer
    /// pass on each of those would be exactly the kind of needless per-frame work that
    /// caused the "update install freakout" performance issues fixed elsewhere.
    @State private var profileTabIcon: UIImage? = nil

    /// Whether `account.avatarImage` is a genuinely multi-frame (animated GIF)
    /// UIImage — recomputed alongside `profileTabIcon` in the same onReceive,
    /// same "don't redo this on every player publish" reasoning as above.
    /// Drives the animated tab-icon overlay below; see its doc comment for why
    /// a real animating view can't just be dropped into `.tabItem{}` directly.
    @State private var avatarIsAnimatedGIF = false

    /// The real on-screen frame of the native `UITabBar`, in `ContentView`'s
    /// own coordinate space. Populated by `TabBarFrameReader` below and used
    /// to position the animated-avatar overlay — reading the actual frame
    /// (rather than assuming the bar spans edge-to-edge and dividing the
    /// full screen width by 5) is what makes the overlay track correctly on
    /// the floating/inset tab bar style, where the bar has margins on both
    /// sides and is narrower than the screen.
    @State private var tabBarFrame: CGRect = .zero

    /// Self "I'm online" heartbeat for the Social Ecosystem presence feature
    /// (POST /api/social/presence every ~45s while foregrounded). Owned here
    /// rather than injected from LumisoundApp — ContentView is the one view
    /// mounted for the app's entire foreground lifetime, so it's the natural
    /// place to start/stop it on login/logout and to fire a best-effort
    /// "going offline" beacon on backgrounding (see the notification
    /// subscriptions at the bottom of `body`). No other view reads this
    /// instance's state, so it isn't injected via `.environmentObject`.
    @StateObject private var presenceService = PresenceService()

    init() {
        // Tab bar — transparent with dark blur
        let tabAppearance = UITabBarAppearance()
        tabAppearance.configureWithTransparentBackground()
        tabAppearance.backgroundEffect = UIBlurEffect(style: .systemThinMaterialDark)
        UITabBar.appearance().standardAppearance = tabAppearance
        UITabBar.appearance().scrollEdgeAppearance = tabAppearance

        // Navigation bar — fully transparent so gallery background shows through.
        // Each NavigationStack also adds .toolbarBackground(.hidden) for the scroll-edge state.
        let navAppearance = UINavigationBarAppearance()
        navAppearance.configureWithTransparentBackground()
        navAppearance.backgroundColor = .clear
        navAppearance.shadowColor = .clear
        UINavigationBar.appearance().standardAppearance = navAppearance
        UINavigationBar.appearance().scrollEdgeAppearance = navAppearance
        UINavigationBar.appearance().compactAppearance = navAppearance

        // List/TableView — clear background so gallery shows through list rows.
        UITableView.appearance().backgroundColor = .clear
    }

    var body: some View {
        ZStack {
            GalleryBackgroundView()
                .ignoresSafeArea()
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Invisible — checks once per install whether the server has a
            // backed-up watched-folder structure for this account and, if so,
            // prompts to redownload tracks back into their original folders.
            RestoreFoldersPromptView()

            TabView(selection: $selectedTab) {

                // MARK: Tab 1 — Library
                LibraryView()
                    .tabItem {
                        Label("Library", systemImage: "music.note.list")
                    }
                    .tag(0)

                // MARK: Tab 2 — Now Playing
                // Icon fills when a song is active to give a quick visual cue.
                NowPlayingView()
                    .tabItem {
                        Label(
                            "Playing",
                            systemImage: player.currentSong != nil
                                ? "play.circle.fill"
                                : "play.circle"
                        )
                    }
                    .tag(1)

                // MARK: Tab 3 — Queue
                QueueView()
                    .tabItem {
                        Label("Queue", systemImage: "list.number")
                    }
                    .tag(2)

                // MARK: Tab 4 — Search Streaming
                StreamSearchView()
                    .tabItem {
                        // Cloud-with-download-arrow better signals this tab's purpose
                        // (downloading from YouTube/SoundCloud/server) than a generic
                        // magnifying glass.
                        Label("Cloud Services", systemImage: "icloud.and.arrow.down")
                    }
                    .tag(3)

                // MARK: Tab 5 — Settings
                // Shows the user's profile photo instead of a generic gearshape once
                // they've uploaded one — gives a quick "is this me?" glance and matches
                // the profile-as-settings-entry convention used by most social/media apps.
                // Falls back to gearshape for logged-out users / no avatar uploaded.
                SettingsView()
                    .tabItem {
                        if let icon = profileTabIcon {
                            Image(uiImage: icon)
                            Text("Settings")
                        } else {
                            Label("Settings", systemImage: "gearshape")
                        }
                    }
                    .tag(4)
            }
            .tint(AppTheme.dynamicAccent)
            // Subtle cross-fade + "pop" scale-in between tabs. iOS 16 doesn't expose
            // a way to animate transitions *between* TabView pages or to animate the
            // native tab-bar icons themselves (`.symbolEffect(.bounce)` needs iOS 17),
            // so this gives the newly-selected tab's content a quick settle-in instead.
            .scaleEffect(tabPopScale)
            .offset(y: tabSlideOffset)
            .opacity(tabContentOpacity)
            .animation(.easeInOut(duration: 0.18), value: selectedTab)
            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: tabPopScale)
            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: tabSlideOffset)
            .animation(.easeInOut(duration: 0.15), value: tabContentOpacity)
            // Crash-context breadcrumb — "what was the user doing right before
            // the crash" is the single most useful fact for diagnosing reports
            // like "it just freezes/crashes sometimes". See AppLogger.breadcrumb.
            .onChange(of: selectedTab) { newValue in
                let names = ["Library", "Playing", "Queue", "Cloud Services", "Settings"]
                appBreadcrumb("Switched to \(names.indices.contains(newValue) ? names[newValue] : "tab \(newValue)") tab")

                // Settle-in transition on the newly-selected tab's content —
                // style picked in Settings → Appearance. iOS 16 doesn't expose
                // a way to animate transitions *between* TabView pages or the
                // native tab-bar icons themselves, so all three styles work by
                // dipping then springing/fading back on the content itself.
                switch TabTransitionStyle(rawValue: tabTransitionStyleRaw) ?? .scalePop {
                case .scalePop:
                    tabPopScale = 0.98
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) {
                        tabPopScale = 1.0
                    }
                case .slide:
                    tabSlideOffset = 14
                    tabContentOpacity = 0.5
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) {
                        tabSlideOffset = 0
                        tabContentOpacity = 1.0
                    }
                case .fadeOnly:
                    tabContentOpacity = 0.3
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) {
                        tabContentOpacity = 1.0
                    }
                }
            }
            // No explicit .frame() on TabView — it must size itself from its content.
            // An explicit frame here can cause stretch/overflow on certain device sizes.

            // MARK: Bridge Health Toast — floats above all content
            if bridgeHealth.showToast {
                VStack {
                    ToastView(message: bridgeHealth.toastMessage, isSuccess: bridgeHealth.toastIsSuccess)
                        .padding(.top, 56)
                        .transition(.move(edge: .top).combined(with: .opacity))
                    Spacer()
                }
                .animation(.spring(response: 0.4, dampingFraction: 0.75), value: bridgeHealth.showToast)
                .allowsHitTesting(false)
            }

            // MARK: App-wide categorized toasts — favorites, playlists, downloads, etc.
            VStack {
                ToastOverlay()
                    .padding(.top, 56)
                Spacer()
            }
            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: toastCenter.current)
            .allowsHitTesting(false)

            // MARK: Animated GIF avatar overlay for the Settings tab icon
            //
            // `.tabItem{}` only accepts `Image`/`Text` content, so the real
            // Settings tabItem above always renders `profileTabIcon` — a
            // static (first-frame) circular crop, same as before this
            // feature. There is no supported way to put a genuinely-animating
            // `UIViewRepresentable` (`AnimatedImageView`) *inside* a native
            // TabView's tab bar item.
            //
            // The fix used here: composite a real `AnimatedImageView` directly
            // ON TOP of that tab item, in the same screen position, whenever
            // the signed-in user's avatar is an actual multi-frame GIF (not
            // just any avatar — a static avatar looks identical either way,
            // so the overlay only exists when it would visibly differ).
            // `.allowsHitTesting(false)` means every tap in that spot still
            // reaches the real TabView underneath untouched — this is purely
            // a cosmetic replacement layer, not a reimplementation of tab
            // selection/highlighting/accessibility, so all 5 tabs stay
            // ordinary, fully-functional SwiftUI TabView items.
            // Invisible probe that keeps `tabBarFrame` synced to the real
            // native UITabBar's on-screen frame every layout pass — see its
            // own doc comment for why this replaced a screen-width guess.
            TabBarFrameReader(frame: $tabBarFrame)
                .frame(width: 0, height: 0)
                .allowsHitTesting(false)

            if avatarIsAnimatedGIF, let avatarImage = account.avatarImage, tabBarFrame != .zero {
                let tabCount: CGFloat = 5
                let tabSlotWidth = tabBarFrame.width / tabCount
                let iconSize: CGFloat = 28
                // Vertical center of a UITabBar icon sits in the upper portion
                // of the bar, above the text label — tuned by eye against the
                // existing `circularProfileIcon` static rendering (this repo
                // has no local Xcode/Simulator to check pixel-for-pixel), but
                // now expressed as a fraction of the *real* bar height instead
                // of an absolute offset from the screen edge, so it still
                // lands correctly whether the bar is edge-to-edge or a
                // floating inset pill.
                let iconVerticalFraction: CGFloat = 0.36
                AnimatedImageView(image: avatarImage, contentMode: .scaleAspectFill)
                    .frame(width: iconSize, height: iconSize)
                    .clipShape(Circle())
                    .position(
                        x: tabBarFrame.minX + tabBarFrame.width - tabSlotWidth / 2,
                        y: tabBarFrame.minY + tabBarFrame.height * iconVerticalFraction
                    )
                    .allowsHitTesting(false)
            }
        }
        .acoustIDConfirmSheet()
        .clipMakerSheet()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .fullScreenCover(isPresented: $showCarMode) {
            CarModeView()
                .environmentObject(player)
        }
        // Floating car-mode button — top-right corner above tab bar content.
        // Hidden entirely when the user disables Car Mode in Settings → Playback.
        .overlay(alignment: .topTrailing) {
            if carModeEnabled {
                Button {
                    showCarMode = true
                } label: {
                    Image(systemName: "car.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(AppTheme.dynamicAccent)
                        .padding(10)
                        .adaptiveGlass(tint: AppTheme.dynamicAccent, in: Circle())
                }
                .padding(.trailing, 16)
                .padding(.top, 56)
            }
        }
        // Auto-activate when a genuine car stereo / CarPlay route becomes available.
        //
        // AVAudioSession posts route-change notifications from an internal audio
        // thread, NOT necessarily the main thread — mutating `@State` here directly
        // is a SwiftUI threading violation ("Publishing changes from background
        // threads is not allowed") that can crash the app the instant *any*
        // Bluetooth device connects or disconnects. Hop to the main actor first.
        //
        // Also narrowed the trigger from "any Bluetooth A2DP device" (which
        // matches ordinary headphones/earbuds too) to `.carAudio` only, so
        // pairing regular Bluetooth headphones no longer force-switches into
        // Car Mode — and guard against re-presenting an already-visible sheet.
        .onReceive(
            NotificationCenter.default.publisher(for: AVAudioSession.routeChangeNotification)
        ) { notification in
            guard
                let reason = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
                AVAudioSession.RouteChangeReason(rawValue: reason) == .newDeviceAvailable
            else { return }
            Task { @MainActor in
                guard carModeEnabled, !showCarMode else { return }
                let outputs = AVAudioSession.sharedInstance().currentRoute.outputs
                let isCarAudio = outputs.contains { $0.portType == .carAudio }
                if isCarAudio { showCarMode = true }
            }
        }
        // Render the tab-bar profile icon once up front and again whenever the
        // avatar changes (login, upload, logout). `account.$avatarImage` is used
        // (Combine subscription) rather than `.onChange(of: account.avatarImage)`
        // since `UIImage` isn't `Equatable`.
        .onAppear {
            profileTabIcon = Self.circularProfileIcon(from: account.avatarImage)
            avatarIsAnimatedGIF = Self.isAnimatedGIF(account.avatarImage)
        }
        .onReceive(account.$avatarImage) { image in
            profileTabIcon = Self.circularProfileIcon(from: image)
            avatarIsAnimatedGIF = Self.isAnimatedGIF(image)
        }
        // MARK: Social Ecosystem — presence heartbeat
        //
        // Starts/stops the "I'm online" polling heartbeat (POST
        // /api/social/presence every ~45s) alongside login state, same
        // start/stop-on-`$isLoggedIn` shape LumisoundApp already uses for
        // `account.startAutoPushTimer`/`stopAutoPushTimer`.
        .onAppear {
            if account.isLoggedIn {
                presenceService.startHeartbeat(account: account, player: player)
            }
        }
        .onReceive(account.$isLoggedIn) { loggedIn in
            if loggedIn {
                presenceService.startHeartbeat(account: account, player: player)
            } else {
                presenceService.stopHeartbeat()
            }
        }
        // Best-effort "going offline" beacon — not guaranteed to land (the
        // process may suspend mid-request), but the server's own 90s
        // presence-freshness window already covers the case where it
        // doesn't (see ios_presence_state's doc comment in schema.sql).
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)) { _ in
            if account.isLoggedIn {
                presenceService.sendGoingOffline(account: account)
            }
        }
        // Resume the heartbeat immediately on return to foreground, rather
        // than waiting up to ~45s for the next scheduled tick.
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            if account.isLoggedIn {
                presenceService.startHeartbeat(account: account, player: player)
            }
        }
    }

    /// Crops `image` to a circle at tab-bar icon size and marks it `.alwaysOriginal`
    /// so SwiftUI renders the user's actual photo instead of template-tinting it
    /// (which is what plain `Image(uiImage:)` would do with a system-style asset).
    /// Always produces a static (first-frame) crop even when `image` is an
    /// animated multi-frame GIF — `UIGraphicsImageRenderer`'s `draw(in:)` only
    /// ever captures one frame — which is fine, since this is only ever used
    /// as the underlying native `.tabItem{}` icon; the animated overlay drawn
    /// on top of it (see `avatarIsAnimatedGIF` in `body`) is what actually plays.
    private static func circularProfileIcon(from image: UIImage?) -> UIImage? {
        guard let image else { return nil }
        let size: CGFloat = 28
        let rect = CGRect(x: 0, y: 0, width: size, height: size)
        let renderer = UIGraphicsImageRenderer(size: rect.size)
        let cropped = renderer.image { _ in
            UIBezierPath(ovalIn: rect).addClip()
            image.draw(in: rect)
        }
        return cropped.withRenderingMode(.alwaysOriginal)
    }

    /// Whether `image` is a genuinely multi-frame `UIImage` — i.e. one
    /// produced by `UIImage.gifImage(data:)` from an actual animated GIF, as
    /// opposed to any static image (JPEG, or a single-frame "GIF"). `.images`
    /// is only ever non-nil on a `UIImage` built via `animatedImage(with:duration:)`.
    private static func isAnimatedGIF(_ image: UIImage?) -> Bool {
        (image?.images?.count ?? 0) > 1
    }
}

// MARK: - TabBarFrameReader

/// Invisible probe view that walks up to the window and back down through
/// its entire view hierarchy to find the real, live `UITabBar` and reports
/// its frame (converted into this view's own coordinate space) via
/// `frame`. Exists because the animated-avatar tab-icon overlay used to
/// assume the tab bar spans the full screen width edge-to-edge — true on
/// older edge-to-edge `UITabBar` styling, but not on the floating/inset
/// pill style (margins on both sides, narrower than the screen), where
/// that assumption placed the overlay to the right of the actual icon.
/// Reading the real frame keeps this correct regardless of tab bar style,
/// device size, or any future Apple redesign, without hardcoding margins.
private struct TabBarFrameReader: UIViewRepresentable {
    @Binding var frame: CGRect

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
        DispatchQueue.main.async { Self.updateFrame(from: view, frame: $frame) }
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        DispatchQueue.main.async { Self.updateFrame(from: uiView, frame: $frame) }
    }

    private static func updateFrame(from view: UIView, frame: Binding<CGRect>) {
        guard let window = view.window, let tabBar = findTabBar(in: window) else { return }
        let converted = tabBar.convert(tabBar.bounds, to: view)
        if converted != frame.wrappedValue {
            frame.wrappedValue = converted
        }
    }

    private static func findTabBar(in view: UIView) -> UITabBar? {
        if let tabBar = view as? UITabBar { return tabBar }
        for subview in view.subviews {
            if let found = findTabBar(in: subview) { return found }
        }
        return nil
    }
}
