import Foundation
import WatchConnectivity
import UIKit

// MARK: - PhoneWatchSync (iOS side)
//
// Pushes Now Playing state to the paired watch companion (mirrors the
// WidgetDataService pattern) and routes transport commands coming back from the
// watch to the player via `commandHandler`. Entirely additive — if no watch is
// paired, every call is a cheap no-op.

@MainActor
final class PhoneWatchSync: NSObject, ObservableObject {
    static let shared = PhoneWatchSync()

    /// Set by the app to route watch commands ("toggle"/"next"/"previous") to the player.
    var commandHandler: ((String) -> Void)?

    private override init() {
        super.init()
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
    }

    func update(song: Song?, isPlaying: Bool, artwork: UIImage?) {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated else { return }
        var ctx: [String: Any] = [
            "title": song?.displayName ?? "",
            "artist": song?.artistName ?? "",
            "isPlaying": isPlaying,
        ]
        if let artwork, let data = Self.thumbnailJPEG(artwork) {
            ctx["artwork"] = data
        } else {
            ctx["clearArtwork"] = true
        }
        try? session.updateApplicationContext(ctx)
    }

    /// Downsizes artwork to a small JPEG so it fits comfortably in the
    /// application-context payload. `maxDim` is in physical pixels — the
    /// previous naive resize (no explicit renderer scale) silently rendered
    /// at the phone's screen scale, tripling the payload's pixel dimensions
    /// (140 → 420px). 240px covers the watch's artwork slot (~120pt @2x)
    /// exactly.
    private static func thumbnailJPEG(_ image: UIImage, maxDim: CGFloat = 240) -> Data? {
        ImageDownsampler.jpegData(image, maxPixelSize: maxDim, compressionQuality: 0.5)
    }

    private func handle(_ payload: [String: Any]) {
        guard let cmd = payload["command"] as? String else { return }
        commandHandler?(cmd)
    }
}

extension PhoneWatchSync: WCSessionDelegate {
    nonisolated func session(_ session: WCSession,
                             activationDidCompleteWith state: WCSessionActivationState,
                             error: Error?) {}

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        Task { @MainActor in self.handle(message) }
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
        Task { @MainActor in self.handle(userInfo) }
    }
}
