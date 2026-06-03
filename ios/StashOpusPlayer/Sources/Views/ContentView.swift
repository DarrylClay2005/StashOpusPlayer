import SwiftUI

struct ContentView: View {

    @EnvironmentObject private var player: AudioPlayerManager
    @EnvironmentObject private var streaming: StreamingService
    @EnvironmentObject private var account: AccountService

    /// Persists the last-selected tab across launches.
    @AppStorage("selected_tab") private var selectedTab = 0

    var body: some View {
        ZStack {
            GalleryBackgroundView()

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
        }
    }
}
