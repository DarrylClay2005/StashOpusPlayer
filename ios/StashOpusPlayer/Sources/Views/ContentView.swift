import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            LibraryView()
                .tabItem {
                    Label("Library", systemImage: "music.note.list")
                }

            NowPlayingView()
                .tabItem {
                    Label("Playing", systemImage: "play.circle")
                }

            QueueView()
                .tabItem {
                    Label("Queue", systemImage: "list.bullet")
                }

            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "slider.horizontal.3")
                }
        }
        .tint(AppTheme.accent)
    }
}
