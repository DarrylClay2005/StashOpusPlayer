import SwiftUI

// MARK: - Lumisound Watch (companion remote)
//
// A lightweight WatchConnectivity remote for the iOS app: it mirrors the phone's
// Now Playing state and sends transport commands back. It deliberately does NOT
// reuse the iOS codebase (UIKit/AVAudioEngine) — it's a thin, self-contained
// companion so it compiles cleanly for watchOS.

@main
struct LumisoundWatchApp: App {
    @StateObject private var connectivity = WatchConnectivityManager.shared

    var body: some Scene {
        WindowGroup {
            WatchNowPlayingView()
                .environmentObject(connectivity)
        }
    }
}
