import SwiftUI
import UIKit

@main
struct StashOpusPlayerApp: App {
    @StateObject private var libraryManager = LibraryManager()
    @StateObject private var player = AudioPlayerManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(libraryManager)
                .environmentObject(player)
                .preferredColorScheme(.dark)
                .task {
                    player.audioSettings = PersistenceService.shared.loadAudioSettings() ?? AudioSettings()
                }
                .onReceive(
                    NotificationCenter.default.publisher(
                        for: UIApplication.didEnterBackgroundNotification
                    )
                ) { _ in
                    PersistenceService.shared.saveAudioSettings(player.audioSettings)
                }
        }
    }
}
