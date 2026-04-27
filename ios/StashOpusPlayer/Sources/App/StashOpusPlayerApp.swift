import SwiftUI

@main
struct StashOpusPlayerApp: App {
    @StateObject private var libraryStore = MusicLibraryStore()
    @StateObject private var player = AudioPlayerManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(libraryStore)
                .environmentObject(player)
                .preferredColorScheme(.dark)
        }
    }
}
