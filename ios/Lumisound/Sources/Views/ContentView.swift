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
    @EnvironmentObject private var social: SocialService
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
        // The native UITabBar itself is hidden (see `.toolbar(.hidden, for:
        // .tabBar)` in `body`) in favor of `CustomTabBar` below, which is
        // what makes a 7th/8th tab a horizontal-scroll rather than getting
        // silently collapsed into iOS's automatic "More" tab (the native
        // UITabBarController does that itself past 5 items on iPhone, with
        // no supported way to opt out short of replacing the bar entirely).
        // No UITabBarAppearance configuration needed here as a result.

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

            // `.tabItem{}` below is vestigial — it's what a *visible* native
            // UITabBar would render, but that bar is hidden (see
            // `.toolbar(.hidden, for: .tabBar)`) in favor of `CustomTabBar`.
            // It's left in place anyway because `.tag()` is what `TabView`
            // uses to route `selection:`, and each `.tabItem{}` still gives
            // VoiceOver a label for the (invisible) native item — harmless
            // either way, just unused visually.
            TabView(selection: $selectedTab) {

                // MARK: Tab 1 — Library
                LibraryView()
                    .toolbar(.hidden, for: .tabBar)
                    .tabItem {
                        Label("Library", systemImage: "music.note.list")
                    }
                    .tag(0)

                // MARK: Tab 2 — Now Playing
                NowPlayingView()
                    .toolbar(.hidden, for: .tabBar)
                    .tabItem {
                        Label("Playing", systemImage: "play.circle")
                    }
                    .tag(1)

                // MARK: Tab 3 — Queue
                QueueView()
                    .toolbar(.hidden, for: .tabBar)
                    .tabItem {
                        Label("Queue", systemImage: "list.number")
                    }
                    .tag(2)

                // MARK: Tab 4 — Search Streaming
                StreamSearchView()
                    .toolbar(.hidden, for: .tabBar)
                    .tabItem {
                        Label("Cloud Services", systemImage: "icloud.and.arrow.down")
                    }
                    .tag(3)

                // MARK: Tab 5 — Friends
                // Its own NavigationStack since FriendsListView (like
                // ProfileView below) is normally pushed from AccountView's
                // Social section rather than hosted as a tab root.
                NavigationStack {
                    FriendsListView()
                        .safeAreaInset(edge: .bottom) { MiniPlayerBar() }
                }
                    .toolbar(.hidden, for: .tabBar)
                    .tabItem {
                        Label("Friends", systemImage: "person.2.fill")
                    }
                    .tag(4)

                // MARK: Tab 6 — Profile
                NavigationStack {
                    ProfileView()
                        .safeAreaInset(edge: .bottom) { MiniPlayerBar() }
                }
                    .toolbar(.hidden, for: .tabBar)
                    .tabItem {
                        Label("Profile", systemImage: "person.crop.circle")
                    }
                    .tag(5)

                // MARK: Tab 7 — Settings
                SettingsView()
                    .toolbar(.hidden, for: .tabBar)
                    .tabItem {
                        Label("Settings", systemImage: "gearshape")
                    }
                    .tag(6)
            }
            // `.toolbar(.hidden, for: .tabBar)` has to be applied to each
            // tab's OWN content (above), not to the TabView itself — it
            // reads as a preference that bubbles up from whichever content
            // is currently on screen, and applying it directly to the
            // TabView container is a no-op the native UITabBar silently
            // ignores. Discovered because doing exactly that in the first
            // pass at this custom bar shipped with the native bar (and its
            // automatic "More" overflow for tabs 5-7) still fully visible
            // underneath the new custom one.
            //
            // Attached directly to the TabView via `.safeAreaInset` so it
            // sits flush against the real system safe area (home
            // indicator) — the bottommost element on screen, same as any
            // normal tab bar. NOTE: a `.safeAreaInset` applied here does
            // NOT propagate down into each tab's own content — SwiftUI/
            // UIKit hosts each `.tabItem{}` page in its own separate
            // hierarchy, and safe-area/environment propagation doesn't
            // cross that boundary. That means each tab's own
            // `.safeAreaInset(edge: .bottom) { MiniPlayerBar() }` has no
            // idea this bar exists and, left alone, places MiniPlayerBar
            // flush against that same real bottom safe area — the two end
            // up stacked in the exact same place instead of MiniPlayerBar
            // sitting above this bar (the correct order — a first attempt
            // at fixing their overlap had this backwards, shifting the tab
            // bar itself up instead of the mini player). Fixed properly in
            // `MiniPlayerBar` itself (see its own doc comment), which now
            // reserves `CustomTabBar.totalHeight` of extra bottom padding
            // so it always renders above this bar rather than trying to
            // make the cross-tab safe-area propagation work (it
            // structurally can't).
            .safeAreaInset(edge: .bottom) {
                CustomTabBar(
                    selectedTab: $selectedTab,
                    hasCurrentSong: player.currentSong != nil,
                    avatarImage: account.avatarImage,
                    incomingFriendRequestCount: social.incomingRequests.count
                )
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
                let names = ["Library", "Playing", "Queue", "Cloud Services", "Friends", "Profile", "Settings"]
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
        // Keeps the Friends tab's request-count badge (in CustomTabBar) fresh
        // without requiring a visit to the Friends tab first — same
        // "refresh on appear + on login" shape as the presence heartbeat below.
        .onAppear {
            Task { await social.fetchFriendRequests() }
        }
        .onReceive(account.$isLoggedIn) { loggedIn in
            if loggedIn {
                Task { await social.fetchFriendRequests() }
            }
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
}

// MARK: - CustomTabBar

/// A fully custom bottom tab bar, replacing the native (hidden) `UITabBar`.
/// Needed once the app grew to 7 tabs — iOS's native `UITabBarController`
/// automatically collapses anything past the 5th item into an unstyled
/// "More" list on iPhone, with no supported way to opt out short of
/// replacing the bar's chrome entirely. Wrapping the row in a horizontal
/// `ScrollView` means it degrades gracefully — spreads evenly across the
/// screen when everything fits (the common case), scrolls instead of
/// clipping when it doesn't (smaller phones, larger Dynamic Type sizes) —
/// rather than ever silently hiding a tab the way the native "More"
/// collapsing would have.
struct CustomTabBar: View {
    @Binding var selectedTab: Int
    let hasCurrentSong: Bool
    let avatarImage: UIImage?
    let incomingFriendRequestCount: Int

    /// The bar's total footprint from the true bottom safe-area edge
    /// (`.frame(height:)` + its own bottom `.padding`) — `MiniPlayerBar`
    /// reserves this much extra bottom padding so it always renders above
    /// this bar rather than the two overlapping. Not `private` for exactly
    /// that cross-file reference; internal (module-wide) is intentional.
    static let totalHeight: CGFloat = 60

    /// Drives the sliding selection pill below via `matchedGeometryEffect` —
    /// shared across every tab button so SwiftUI animates the *same* pill
    /// moving from the old selected button's frame to the new one, instead
    /// of one pill fading out while a separate one fades in at the new spot.
    @Namespace private var selectionNamespace

    private struct TabSpec {
        let tag: Int
        let title: String
        let systemImage: String
    }

    private var specs: [TabSpec] {
        [
            TabSpec(tag: 0, title: "Library", systemImage: "music.note.list"),
            TabSpec(tag: 1, title: "Playing", systemImage: hasCurrentSong ? "play.circle.fill" : "play.circle"),
            TabSpec(tag: 2, title: "Queue", systemImage: "list.number"),
            TabSpec(tag: 3, title: "Cloud Services", systemImage: "icloud.and.arrow.down"),
            TabSpec(tag: 4, title: "Friends", systemImage: "person.2.fill"),
            TabSpec(tag: 5, title: "Profile", systemImage: "person.crop.circle"),
            TabSpec(tag: 6, title: "Settings", systemImage: "gearshape"),
        ]
    }

    var body: some View {
        GeometryReader { outerGeo in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 2) {
                    ForEach(specs, id: \.tag) { spec in
                        tabButton(spec)
                            .frame(maxWidth: .infinity)
                    }
                }
                // Forces the row to spread evenly across the bar's real
                // available width when everything fits (a plain HStack in a
                // ScrollView would otherwise hug the leading edge instead of
                // filling the bar like a normal tab bar), while still
                // letting it grow past that width — and scroll — if the
                // content needs more room than the screen has.
                .frame(minWidth: max(outerGeo.size.width - 12, 0))
                .padding(.horizontal, 6)
            }
        }
        .frame(height: 58)
        .adaptiveGlass(in: Capsule(), fallback: AppTheme.surface)
        .padding(.horizontal, 10)
        .padding(.bottom, 2)
    }

    @ViewBuilder
    private func tabButton(_ spec: TabSpec) -> some View {
        Button {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) {
                selectedTab = spec.tag
            }
        } label: {
            VStack(spacing: 3) {
                ZStack(alignment: .topTrailing) {
                    iconView(for: spec)
                    if spec.tag == 4, incomingFriendRequestCount > 0 {
                        Text("\(min(incomingFriendRequestCount, 99))")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(3)
                            .background(AppTheme.error, in: Circle())
                            .offset(x: 9, y: -6)
                    }
                }
                Text(spec.title)
                    .font(.system(size: 10, weight: selectedTab == spec.tag ? .semibold : .regular))
                    .lineLimit(1)
                    .fixedSize()
            }
            // Only the text/icon *color* changes for the selected tab —
            // matching the plain native tab bar's look — the sliding glass
            // highlight below is scoped to just the icon (see `iconView`),
            // not this whole button, so it never covers the label.
            .foregroundStyle(selectedTab == spec.tag ? AppTheme.dynamicAccent : AppTheme.textSecondary)
            .padding(.vertical, 6)
            .frame(minWidth: 58)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// The Profile tab (tag 5) shows the user's real avatar instead of a
    /// system symbol — animated live via `AnimatedImageView` when it's a
    /// genuine multi-frame GIF, which is the entire point of this custom
    /// bar existing: a native `.tabItem{}` only ever accepts `Image`/`Text`
    /// content, so there was previously no supported way to make a tab
    /// icon actually animate without compositing a second view on top of
    /// the real (hidden) tab bar at a guessed screen position.
    @ViewBuilder
    private func iconView(for spec: TabSpec) -> some View {
        let isSelected = selectedTab == spec.tag
        Group {
            if spec.tag == 5, let avatarImage {
                Group {
                    if (avatarImage.images?.count ?? 0) > 1 {
                        AnimatedImageView(image: avatarImage, contentMode: .scaleAspectFill)
                    } else {
                        Image(uiImage: avatarImage)
                            .resizable()
                            .scaledToFill()
                    }
                }
                .frame(width: 22, height: 22)
                .clipShape(Circle())
            } else {
                Image(systemName: spec.systemImage)
                    .font(.system(size: 19))
                    .frame(width: 22, height: 22)
            }
        }
        // Fixed, modest 34×34 tap/highlight target around JUST the icon —
        // explicitly sized (not inherited from the button's full frame) so
        // the sliding selection pill is a small "bubble" behind the icon
        // like a native Liquid Glass tab bar, not a shape that can inherit
        // some other ambient/ideal size. A first pass at this let the pill
        // balloon into a giant circle that covered the icon AND the label
        // text underneath it — this fixed frame is what prevents that.
        .frame(width: 34, height: 34)
        .background {
            if isSelected {
                Color.clear
                    .adaptiveGlass(tint: AppTheme.dynamicAccent.opacity(0.5), in: Circle(), fallback: AppTheme.dynamicAccent.opacity(0.18))
                    .matchedGeometryEffect(id: "selectedTabPill", in: selectionNamespace)
                    // Explicit animation tied directly to the same state
                    // this pill's presence depends on — a defensive backstop
                    // in case the transaction from `withAnimation` in the
                    // button's action doesn't carry through cleanly (e.g. if
                    // `selectedTab` changes from somewhere else, like
                    // MiniPlayerBar jumping to the Playing tab).
                    .animation(.spring(response: 0.32, dampingFraction: 0.78), value: selectedTab)
            }
        }
    }
}
