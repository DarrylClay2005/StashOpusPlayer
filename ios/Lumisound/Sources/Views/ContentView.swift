import SwiftUI
import UIKit

struct ContentView: View {

    @EnvironmentObject private var player: AudioPlayerManager
    @EnvironmentObject private var streaming: StreamingService
    @EnvironmentObject private var account: AccountService
    @EnvironmentObject private var bridgeHealth: BridgeHealthService

    /// Persists the last-selected tab across launches.
    @AppStorage("selected_tab") private var selectedTab = 0

    init() {
        // Must be set before first render — onAppear fires too late
        let appearance = UITabBarAppearance()
        appearance.configureWithTransparentBackground()
        appearance.backgroundEffect = UIBlurEffect(style: .systemThinMaterialDark)
        UITabBar.appearance().standardAppearance = appearance
        UITabBar.appearance().scrollEdgeAppearance = appearance
    }

    var body: some View {
        ZStack {
            GalleryBackgroundView()
                .ignoresSafeArea()
                .frame(maxWidth: .infinity, maxHeight: .infinity)

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
                SettingsView()
                    .tabItem {
                        Label("Settings", systemImage: "gearshape")
                    }
                    .tag(4)
            }
            .tint(AppTheme.dynamicAccent)
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
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
