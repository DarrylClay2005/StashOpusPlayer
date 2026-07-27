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
    /// Mirrors the phone's active Lua theme preset accent, if any (see
    /// `PhoneWatchSync.update(song:isPlaying:artwork:)`) — `nil` when no
    /// preset is active, in which case the UI just uses its normal default
    /// tint.
    @Published var accentColor: Color?

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
        if let hex = context["accentColorHex"] as? String {
            accentColor = Self.color(fromHex: hex)
        }
        // Mirror into the watch's local app-group storage so the complication
        // (a separate WidgetKit extension target — see WatchWidget/Sources)
        // can show the phone-mirrored Now Playing state too. Only re-push when
        // this particular context update actually carried Now Playing keys —
        // an account-handoff-only payload (below) shouldn't trigger a reload
        // with stale/unrelated values.
        if context["title"] != nil || context["isPlaying"] != nil {
            WatchWidgetDataService.update(title: title, artist: artist, isPlaying: isPlaying)
        }

        // Account handoff pushed by PhoneWatchSync (phone side, additive —
        // see PhoneWatchSync.pushAccountHandoffIfNeeded) — lets the user use
        // the standalone Watch Library without typing credentials on-watch.
        if context["accountTokenCleared"] as? Bool == true {
            WatchAccountStore.shared.clearHandoff()
        } else if context["bridgeURL"] != nil || context["accountToken"] != nil {
            WatchAccountStore.shared.applyHandoff(
                bridgeURL: context["bridgeURL"] as? String,
                token: context["accountToken"] as? String
            )
        }
    }

    /// Minimal `#RRGGBB` -> `Color` parser — this target has no dependency
    /// on the phone app's own `Color(hex:)` (a different module/target), so
    /// a tiny standalone one lives here instead of pulling in that file.
    private static func color(fromHex hex: String) -> Color? {
        let stripped = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard stripped.count == 6 else { return nil }
        var value: UInt64 = 0
        guard Scanner(string: stripped).scanHexInt64(&value) else { return nil }
        let r = Double((value >> 16) & 0xFF) / 255
        let g = Double((value >> 8) & 0xFF) / 255
        let b = Double(value & 0xFF) / 255
        return Color(red: r, green: g, blue: b)
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
