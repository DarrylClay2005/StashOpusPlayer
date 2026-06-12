import Foundation

extension URLRequest {
    /// Lumisound's bridge is exposed via a free ngrok static domain. Without
    /// this header, ngrok's edge intercepts every request (even API calls)
    /// with its browser-warning interstitial and returns HTTP 403 before the
    /// request ever reaches the bridge server. Apply it to every bridge request.
    mutating func addNgrokBypassHeader() {
        setValue("true", forHTTPHeaderField: "ngrok-skip-browser-warning")
    }
}
