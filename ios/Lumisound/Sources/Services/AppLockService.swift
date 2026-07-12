import Foundation
import LocalAuthentication
import SwiftUI

/// Gates the whole app behind Face ID/Touch ID/device passcode when enabled
/// in Settings. The app now syncs personal account data (playlists, listening
/// history, favorites) to the bridge server, so a local screen lock has real
/// value beyond what iOS's own device lock already provides — e.g. a shared
/// device, or someone picking up an already-unlocked phone.
@MainActor
final class AppLockService: ObservableObject {

    static weak var shared: AppLockService?

    private enum Keys {
        static let enabled = "app_lock_enabled"
    }

    @Published var isEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: Keys.enabled)
            // Turning it on locks immediately; turning it off should never
            // leave a stale "locked" state blocking the app.
            isUnlocked = !isEnabled
        }
    }

    /// True once the current session has been authenticated (or locking is
    /// off). Drives the full-screen `AppLockView` overlay in `LumisoundApp`.
    @Published var isUnlocked: Bool

    /// True while a Face ID/Touch ID/passcode prompt is in flight, so a rapid
    /// foreground/background flicker can't fire a second concurrent prompt.
    @Published private(set) var isAuthenticating = false

    init() {
        let enabled = UserDefaults.standard.bool(forKey: Keys.enabled)
        isEnabled = enabled
        isUnlocked = !enabled
        Self.shared = self
    }

    /// Whether the device can evaluate biometrics/passcode at all — used to
    /// hide the Settings toggle on a device with no passcode set (which
    /// LocalAuthentication refuses to enroll against).
    func biometryAvailable() -> Bool {
        LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: nil)
    }

    /// Human-readable name of the enrolled biometry, for the Settings label
    /// ("Require Face ID" vs. "Require Touch ID" vs. a passcode-only fallback).
    var biometryTypeName: String {
        let context = LAContext()
        _ = context.canEvaluatePolicy(.deviceOwnerAuthentication, error: nil)
        switch context.biometryType {
        case .faceID: return "Face ID"
        case .touchID: return "Touch ID"
        case .opticID: return "Optic ID"
        default: return "Passcode"
        }
    }

    /// Marks the app as locked. Called when the scene leaves `.active`.
    /// No-op if locking is off.
    func lock() {
        guard isEnabled else { return }
        isUnlocked = false
    }

    /// Prompts Face ID/Touch ID, falling back to the device passcode
    /// automatically (`.deviceOwnerAuthentication`). Safe to call repeatedly
    /// — coalesces concurrent calls via `isAuthenticating`.
    func authenticate() async {
        guard isEnabled, !isUnlocked, !isAuthenticating else { return }
        isAuthenticating = true
        defer { isAuthenticating = false }

        let context = LAContext()
        context.localizedFallbackTitle = "Use Passcode"

        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: nil) else {
            // No passcode set on the device at all — LocalAuthentication has
            // nothing to check against. Don't permanently lock the user out
            // of their own app over a device configuration this app doesn't
            // control; just let them in.
            isUnlocked = true
            return
        }

        // LocalAuthentication predates Swift concurrency and only exposes a
        // completion-handler API — no native `async throws` overload exists.
        let success = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Unlock Lumisound") { success, _ in
                continuation.resume(returning: success)
            }
        }
        if success { isUnlocked = true }
    }
}
