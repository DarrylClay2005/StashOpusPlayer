import SwiftUI

// MARK: - Lumisound for Apple TV
//
// A focused, self-contained tvOS client: search the Lumisound bridge and stream
// results to the TV via the bridge's /api/stream/proxy endpoint (which serves
// the audio from the bridge's IP so it actually plays). Deliberately does not
// reuse the iOS codebase so it compiles cleanly for tvOS.

@main
struct LumisoundTVApp: App {
    init() {
        TVAppLogger.shared.configure(bridgeURL: TVBridgeClient.shared.baseURL)
    }

    var body: some Scene {
        WindowGroup {
            TVContentView()
        }
    }
}
