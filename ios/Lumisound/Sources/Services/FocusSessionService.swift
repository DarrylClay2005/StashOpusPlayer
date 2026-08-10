import Foundation
import UserNotifications

/// A Pomodoro-style work/break timer tied to playback — plays a chosen set
/// of songs during each work block, pauses for the break, and repeats for a
/// chosen number of rounds. Complements `SleepTimerService`/
/// `SleepWakeAlarmService` (which are about sleeping/waking) with the same
/// idea applied to focused work sessions instead. Uses `AudioPlayerManager
/// .shared`/`LibraryManager.shared` directly rather than being wired up
/// from `LumisoundApp.swift`, same reasoning as `SleepWakeAlarmService`'s
/// `beginWakePlayback()` — this only ever needs to reach a playing app, not
/// participate in dependency injection.
///
/// Like `SleepWakeAlarmService`, a phase transition while the app is fully
/// backgrounded/killed is only guaranteed via the local notification
/// scheduled for it (`UNTimeIntervalNotificationTrigger`) — the in-process
/// `Timer` that actually flips `phase` and touches playback only fires if
/// the process is still alive, the same real iOS limitation stated there.
enum FocusPhase: Equatable {
    case idle
    case working(round: Int)
    case onBreak(round: Int)
    case finished
}

@MainActor
final class FocusSessionService: ObservableObject {
    static let shared = FocusSessionService()

    private static let completedSessionsKey = "focusSessions.completedCount"
    private static let notificationID = "focusSession.transition"

    @Published private(set) var phase: FocusPhase = .idle
    @Published private(set) var phaseEndsAt: Date?
    @Published private(set) var totalRounds: Int = 4
    @Published private(set) var completedSessions: Int

    private var phaseTimer: Timer?
    private var workDuration: TimeInterval = 25 * 60
    private var breakDuration: TimeInterval = 5 * 60
    private var sessionSongs: [Song] = []

    private init() {
        completedSessions = UserDefaults.standard.integer(forKey: Self.completedSessionsKey)
    }

    var isActive: Bool {
        switch phase {
        case .idle, .finished: return false
        case .working, .onBreak: return true
        }
    }

    /// Starts a new session, replacing any in-progress one. `songs` empty
    /// means "don't touch playback during work blocks" — the break phase
    /// still pauses either way, since a break is meant to be quiet.
    func start(workMinutes: Int, breakMinutes: Int, rounds: Int, songs: [Song]) {
        phaseTimer?.invalidate()
        workDuration = TimeInterval(max(1, workMinutes) * 60)
        breakDuration = TimeInterval(max(1, breakMinutes) * 60)
        totalRounds = max(1, rounds)
        sessionSongs = songs
        beginPhase(.working(round: 1))
    }

    func cancel() {
        phaseTimer?.invalidate()
        phaseTimer = nil
        phase = .idle
        phaseEndsAt = nil
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [Self.notificationID])
    }

    private func beginPhase(_ newPhase: FocusPhase) {
        phase = newPhase
        let duration: TimeInterval
        switch newPhase {
        case .working:
            duration = workDuration
            if !sessionSongs.isEmpty {
                AudioPlayerManager.shared?.setQueue(sessionSongs, startIndex: 0, autoplay: true)
            }
        case .onBreak:
            duration = breakDuration
            AudioPlayerManager.shared?.pause()
        case .idle, .finished:
            duration = 0
        }

        phaseEndsAt = duration > 0 ? Date().addingTimeInterval(duration) : nil
        scheduleTransitionNotification(currentPhase: newPhase, duration: duration)

        guard duration > 0 else { return }
        phaseTimer?.invalidate()
        phaseTimer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in self?.advance() }
        }
    }

    private func advance() {
        switch phase {
        case .working(let round):
            if round >= totalRounds {
                finish()
            } else {
                beginPhase(.onBreak(round: round))
            }
        case .onBreak(let round):
            beginPhase(.working(round: round + 1))
        case .idle, .finished:
            break
        }
    }

    private func finish() {
        phaseTimer?.invalidate()
        phaseTimer = nil
        phase = .finished
        phaseEndsAt = nil
        AudioPlayerManager.shared?.pause()
        completedSessions += 1
        UserDefaults.standard.set(completedSessions, forKey: Self.completedSessionsKey)
    }

    /// Schedules a notification announcing the transition AWAY from
    /// `currentPhase`, firing `duration` seconds from now — e.g. while
    /// `currentPhase` is `.working`, this announces the upcoming break.
    private func scheduleTransitionNotification(currentPhase: FocusPhase, duration: TimeInterval) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [Self.notificationID])
        guard NotificationService.shared.isAuthorized, duration > 1 else { return }

        let content = UNMutableNotificationContent()
        switch currentPhase {
        case .working:
            content.title = "Break Time"
            content.body = "Nice work — take a break."
        case .onBreak:
            content.title = "Back to Work"
            content.body = "Break's over — let's get back to it."
        case .idle, .finished:
            return
        }
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: duration, repeats: false)
        let request = UNNotificationRequest(identifier: Self.notificationID, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                appWarn("FocusSessionService: failed to schedule transition notification: \(error.localizedDescription)", category: "notifications")
            }
        }
    }
}
