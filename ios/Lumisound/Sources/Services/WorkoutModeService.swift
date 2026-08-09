import CoreMotion
import Foundation

// MARK: - WorkoutModeService
//
// BPM-synced playback speed: tracks live step cadence via CMPedometer and
// nudges the current track's playback speed (AudioPlayerManager.audioSettings
// .speed — the same pitch-preserving rate every playback tier already
// applies, see AudioPlayerManager+ApplySettings.swift) so the music's
// effective tempo tracks the user's pace, using BPMAnalyzerService (already
// used for BPM badges/harmonic mixing) as the track's tempo reference. No
// new audio pipeline — this only ever adjusts a knob every tier already
// reads.
@MainActor
final class WorkoutModeService: ObservableObject {
    static let shared = WorkoutModeService()

    @Published private(set) var isActive = false
    @Published private(set) var currentCadenceSPM: Double?
    @Published private(set) var lastError: String?

    private let pedometer = CMPedometer()
    private var windowStartDate: Date?
    private var windowStartSteps: Int = 0

    /// Playback speed is clamped to this range regardless of how far
    /// cadence and track BPM diverge — outside it, tempo-matching stops
    /// sounding like "the song adapted to my pace" and starts sounding like
    /// a chipmunk/slow-motion effect, defeating the point.
    private static let speedClampRange: ClosedRange<Double> = 0.85...1.25

    /// How much cadence history to average over before nudging speed again
    /// — long enough that one mis-detected step doesn't cause an audible
    /// speed jump, short enough to still track a real pace change (speeding
    /// up/slowing down) within a lap or two.
    private static let cadenceWindowSeconds: TimeInterval = 12

    private init() {}

    var isAvailable: Bool { CMPedometer.isStepCountingAvailable() }

    /// Starts tracking cadence and adjusting playback speed. No-op if
    /// already active or step counting isn't available on this device.
    func start() {
        guard !isActive, isAvailable else { return }
        isActive = true
        lastError = nil
        windowStartDate = Date()
        windowStartSteps = 0

        pedometer.startUpdates(from: Date()) { [weak self] data, error in
            guard let self else { return }
            Task { @MainActor in
                if let error {
                    self.lastError = error.localizedDescription
                    return
                }
                guard let data else { return }
                self.handlePedometerUpdate(steps: data.numberOfSteps.intValue)
            }
        }
    }

    /// Stops tracking and restores the track's natural (1.0×) speed —
    /// leaving whatever workout-adjusted rate was last applied would be a
    /// surprising, sticky side effect once the user is done exercising.
    func stop() {
        guard isActive else { return }
        isActive = false
        pedometer.stopUpdates()
        currentCadenceSPM = nil
        AudioPlayerManager.shared?.audioSettings.speed = 1.0
    }

    private func handlePedometerUpdate(steps: Int) {
        guard let windowStartDate else { return }
        let elapsed = Date().timeIntervalSince(windowStartDate)
        // A near-zero window makes the steps-per-minute estimate wildly
        // noisy (a single early step reads as an absurd cadence) — wait for
        // a few real seconds of data before trusting it.
        guard elapsed >= 3 else { return }

        let stepsInWindow = steps - windowStartSteps
        let spm = Double(stepsInWindow) / (elapsed / 60)
        currentCadenceSPM = spm

        if elapsed >= Self.cadenceWindowSeconds {
            // Slide the window forward rather than accumulating for the
            // whole workout, so cadence tracks a recent pace change instead
            // of an average since `start()` was called.
            self.windowStartDate = Date()
            self.windowStartSteps = steps
        }

        applySpeed(forCadence: spm)
    }

    private func applySpeed(forCadence spm: Double) {
        guard let player = AudioPlayerManager.shared,
              let url = player.currentSong?.url else { return }

        Task {
            guard let bpm = await BPMAnalyzerService.shared.bpm(for: url), bpm > 0 else { return }
            // Cadence roughly tracks either the track's own BPM (walking to
            // a slow song, 1:1) or double it (a fast running cadence
            // against a half-time-feel track) — pick whichever reference is
            // closer to the actual cadence before computing the ratio, so a
            // 170 spm cadence against an 85 BPM track matches at 2:1 rather
            // than forcing a ~2× playback rate to hit a 1:1 match.
            let reference = abs(spm - bpm) <= abs(spm - bpm * 2) ? bpm : bpm * 2
            guard reference > 0 else { return }
            let rawRatio = spm / reference
            let clampedRatio = min(max(rawRatio, Self.speedClampRange.lowerBound), Self.speedClampRange.upperBound)
            await MainActor.run {
                guard self.isActive else { return }
                player.audioSettings.speed = clampedRatio
            }
        }
    }
}
