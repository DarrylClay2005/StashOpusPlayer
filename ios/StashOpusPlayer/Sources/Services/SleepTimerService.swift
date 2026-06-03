import Foundation
import Combine

@MainActor
final class SleepTimerService: ObservableObject {
    @Published private(set) var isActive = false
    @Published private(set) var remainingSeconds: TimeInterval = 0
    @Published var selectedDuration: TimeInterval = 30 * 60
    /// Set to `true` for one tick when the timer expires; AudioPlayerManager observes this.
    @Published private(set) var didExpire = false

    static let presets: [(label: String, seconds: TimeInterval)] = [
        ("5 min",  5  * 60),
        ("15 min", 15 * 60),
        ("30 min", 30 * 60),
        ("45 min", 45 * 60),
        ("1 hr",   60 * 60),
        ("90 min", 90 * 60),
    ]

    private var timer: Timer?

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
    }

    func cancel() {
        timer?.invalidate()
        timer = nil
        isActive = false
        remainingSeconds = 0
        didExpire = false
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
            didExpire = true
            // Reset the flag after one run loop so observers don't re-trigger.
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 100_000_000)
                self.didExpire = false
            }
        }
    }
}
