import GroupActivities
import Foundation

// MARK: - Live reactions for Listen Together
//
// Lightweight, ephemeral emoji reactions broadcast during a SharePlay
// session — same `GroupSessionMessenger` as `PlaybackSyncMessage`/the
// shared queue in `SharePlayCoordinator+Queue.swift`, just a fire-and-forget
// event rather than persisted state: nothing here is stored, retried, or
// synced on join. A participant who joins mid-session simply doesn't see
// reactions sent before they arrived, same as joining a live chat late —
// that's fine, these are meant to be felt in the moment ("everyone reacts
// to the drop together"), not a record of anything.

private struct ReactionMessage: Codable {
    var emoji: String
}

extension SharePlayCoordinator {
    func subscribeReactionMessages(messenger: GroupSessionMessenger) {
        let task = Task { [weak self] in
            for await (message, _) in messenger.messages(of: ReactionMessage.self) {
                self?.reactionReceived.send(message.emoji)
            }
        }
        tasks.append(task)
    }

    /// Broadcasts `emoji` to the group and fires it locally too, so the
    /// sender's own tap animates immediately rather than waiting on a
    /// round trip through the messenger.
    func sendReaction(_ emoji: String) {
        guard isSessionActive, let messenger else { return }
        reactionReceived.send(emoji)
        let message = ReactionMessage(emoji: emoji)
        Task { try? await messenger.send(message) }
    }
}
