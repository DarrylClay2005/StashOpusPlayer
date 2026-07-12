import SwiftUI

// MARK: - Lumisound Watch (companion remote + standalone player)
//
// A lightweight WatchConnectivity remote for the iOS app: it mirrors the phone's
// Now Playing state and sends transport commands back. It deliberately does NOT
// reuse the iOS codebase (UIKit/AVAudioEngine) — it's a thin, self-contained
// companion so it compiles cleanly for watchOS.
//
// It ALSO supports fully standalone playback of the user's Personal Cloud
// Library (WatchAccountStore + WatchBridgeClient + WatchLocalPlayerManager +
// WatchLibraryView) — independent of the phone being reachable or even
// paired, once a bridge session exists on-watch (via automatic phone handoff
// or manual on-watch login).

@main
struct LumisoundWatchApp: App {
    @StateObject private var connectivity = WatchConnectivityManager.shared
    @StateObject private var account = WatchAccountStore.shared
    @StateObject private var player = WatchLocalPlayerManager.shared

    var body: some Scene {
        WindowGroup {
            WatchRootView()
                .environmentObject(connectivity)
                .environmentObject(account)
                .environmentObject(player)
        }
    }
}
