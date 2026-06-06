import Foundation
import Combine

@MainActor
final class SleepTimerService: ObservableObject {
    @Published private(set) var isActive = false
    @Published private(set) var remainingSeconds: TimeInterval = 0
    @Published var selectedDuration: TimeInterval = 30 * 60
    /// Set to `true` for one tick when the timer expires; AudioPlayerManager observes this.
    @Published private(set) var didExpire = false
    /// `true` while the 60-second volume fade-out is in progress.
    @Published private(set) var isFading = false

    static let presets: [(label: String, seconds: TimeInterval)] = [
        ("5 min",  5  * 60),
        ("15 min", 15 * 60),
        ("30 min", 30 * 60),
        ("45 min", 45 * 60),
        ("1 hr",   60 * 60),
        ("90 min", 90 * 60),
    ]

    private var timer: Timer?
    private var fadeTimer: Timer?

    // Closure called to read/write the player's current volume so the service
    // stays decoupled from AudioPlayerManager's concrete type.
    var getVolume: (() -> Float)?
    var setVolume: ((Float) -> Void)?
    /// Called after the fade reaches zero — should pause/stop playback.
    var onExpire: (() -> Void)?

    func start(duration: TimeInterval? = nil) {
        let d = duration ?? selectedDuration
        selectedDuration = d
        remainingSeconds = d
        isActive = true
        didExpire = false
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.tick() }
        }
        appLog("SleepTimer: started for \(Int(d))s (\(formattedRemaining))", category: "general")
    }

    func cancel() {
        timer?.invalidate()
        timer = nil
        stopFade(restoreVolume: true)
        isActive = false
        remainingSeconds = 0
        didExpire = false
        appLog("SleepTimer: cancelled", category: "general")
    }

    var formattedRemaining: String {
        guard remainingSeconds > 0 else { return "0:00" }
        let total = Int(remainingSeconds)
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        return h > 0
            ? String(format: "%d:%02d:%02d", h, m, s)
            : String(format: "%d:%02d", m, s)
    }

    private func tick() {
        guard isActive, remainingSeconds > 0 else { return }
        remainingSeconds -= 1
        if remainingSeconds <= 0 {
            timer?.invalidate()
            timer = nil
            isActive = false
            appLog("SleepTimer: expired — beginning fade", category: "general")
            beginFade()
        }
    }

    // MARK: - Volume Fade

    private static let fadeDurationSeconds: Double = 60.0
    private static let fadeStepInterval: Double = 0.5
    private static let fadeStepCount: Int = Int(fadeDurationSeconds / fadeStepInterval) // 120 steps

    /// Volume level captured just before the fade starts so it can be restored on cancel.
    private var volumeBeforeFade: Float = 1.0
    /// Counts how many fade steps have fired.
    private var fadeStep: Int = 0

    private func beginFade() {
        guard !isFading else { return }
        volumeBeforeFade = getVolume?() ?? 1.0
        fadeStep = 0
        isFading = true

        fadeTimer?.invalidate()
        fadeTimer = Timer.scheduledTimer(
            withTimeInterval: Self.fadeStepInterval,
            repeats: true
        ) { [weak self] t in
            Task { @MainActor [weak self] in
                guard let self else { t.invalidate(); return }
                self.applyFadeStep(timer: t)
            }
        }
    }

    private func applyFadeStep(timer t: Timer) {
        fadeStep += 1
        let progress = Float(fadeStep) / Float(Self.fadeStepCount)
        let clipped = min(max(progress, 0), 1)
        let newVolume = volumeBeforeFade * (1.0 - clipped)
        setVolume?(newVolume)

        if fadeStep >= Self.fadeStepCount {
            t.invalidate()
            fadeTimer = nil
            isFading = false
            setVolume?(0)
            onExpire?()
            // Restore volume so it isn't stuck at 0 when the user presses Play again.
            setVolume?(volumeBeforeFade)
            didExpire = true
            appLog("SleepTimer: fade complete — playback stopped", category: "general")
            // Reset the flag after one run loop so observers don't re-trigger.
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 100_000_000)
                self.didExpire = false
            }
        }
    }

    /// Stops an in-progress fade. If `restoreVolume` is true, returns volume to pre-fade level.
    private func stopFade(restoreVolume: Bool) {
        guard isFading else { return }
        fadeTimer?.invalidate()
        fadeTimer = nil
        isFading = false
        if restoreVolume {
            setVolume?(volumeBeforeFade)
        }
    }
}
