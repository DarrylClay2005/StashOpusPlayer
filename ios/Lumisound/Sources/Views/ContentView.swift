import AVFoundation
import SwiftUI
import UIKit

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
                        Label("Search", systemImage: "magnifyingglass")
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
            .animation(.easeInOut(duration: 0.18), value: selectedTab)
            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: tabPopScale)
            // Crash-context breadcrumb — "what was the user doing right before
            // the crash" is the single most useful fact for diagnosing reports
            // like "it just freezes/crashes sometimes". See AppLogger.breadcrumb.
            .onChange(of: selectedTab) { newValue in
                let names = ["Library", "Playing", "Queue", "Search", "Settings"]
                appBreadcrumb("Switched to \(names.indices.contains(newValue) ? names[newValue] : "tab \(newValue)") tab")

                // Quick scale "pop" — dip down then spring back to 1.0 — gives the
                // newly-selected tab a tactile settle-in feel.
                tabPopScale = 0.98
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) {
                    tabPopScale = 1.0
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
        }
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
        }
        .onReceive(account.$avatarImage) { image in
            profileTabIcon = Self.circularProfileIcon(from: image)
        }
    }

    /// Crops `image` to a circle at tab-bar icon size and marks it `.alwaysOriginal`
    /// so SwiftUI renders the user's actual photo instead of template-tinting it
    /// (which is what plain `Image(uiImage:)` would do with a system-style asset).
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
}
