import SwiftUI

// MARK: - WatchRootView
//
// Top-level tab container: "Now Playing" (remote mirror, or standalone
// transport once a Watch Library track is active) and "Library" (standalone
// cloud-track browse/download/play, independent of the phone).

struct WatchRootView: View {
    var body: some View {
        TabView {
            WatchNowPlayingView()
                .tag(0)
            WatchLibraryView()
                .tag(1)
        }
    }
}
