import Foundation
import WatchConnectivity
import SwiftUI

// MARK: - WatchConnectivityManager (watch side)
//
// Receives Now Playing state pushed by the phone (via updateApplicationContext /
// sendMessage) and sends transport commands back. Published properties drive the
// SwiftUI UI.

@MainActor
final class WatchConnectivityManager: NSObject, ObservableObject {
    static let shared = WatchConnectivityManager()

    @Published var title: String = ""
    @Published var artist: String = ""
    @Published var isPlaying: Bool = false
    @Published var artworkData: Data?
    @Published var reachable: Bool = false

    private override init() {
        super.init()
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
    }

    /// Sends a transport command to the phone. Uses the live channel when the
    /// phone is reachable, falling back to a queued user-info transfer otherwise.
    func send(command: String) {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        let payload = ["command": command]
        if session.isReachable {
            session.sendMessage(payload, replyHandler: nil, errorHandler: { _ in
                session.transferUserInfo(payload)
            })
        } else {
            session.transferUserInfo(payload)
        }
    }

    fileprivate func apply(_ context: [String: Any]) {
        if let t = context["title"] as? String { title = t }
        if let a = context["artist"] as? String { artist = a }
        if let p = context["isPlaying"] as? Bool { isPlaying = p }
        if let data = context["artwork"] as? Data { artworkData = data }
        // An empty artwork marker clears stale art when nothing is playing.
        if (context["artwork"] as? Data) == nil, context["clearArtwork"] as? Bool == true {
            artworkData = nil
        }
    }
}

// MARK: - WCSessionDelegate
//
// watchOS only requires `activationDidCompleteWith`. Delegate callbacks arrive on
// a background queue, so each hops to the main actor before touching @Published.
extension WatchConnectivityManager: WCSessionDelegate {
    nonisolated func session(_ session: WCSession,
                             activationDidCompleteWith state: WCSessionActivationState,
                             error: Error?) {
        let isReachable = session.isReachable
        Task { @MainActor in self.reachable = isReachable }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        let isReachable = session.isReachable
        Task { @MainActor in self.reachable = isReachable }
    }

    nonisolated func session(_ session: WCSession,
                             didReceiveApplicationContext applicationContext: [String: Any]) {
        Task { @MainActor in self.apply(applicationContext) }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        Task { @MainActor in self.apply(message) }
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
        Task { @MainActor in self.apply(userInfo) }
    }
}
