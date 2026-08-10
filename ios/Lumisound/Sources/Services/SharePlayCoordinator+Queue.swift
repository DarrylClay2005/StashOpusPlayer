import GroupActivities
import Foundation

// MARK: - Collaborative Up Next queue for Listen Together
//
// `SharePlayCoordinator` (see SharePlayCoordinator.swift) previously only
// synced whichever single track the *host's* device was playing — there was
// no way for other participants to queue something up. This adds a shared
// "suggest a track, upvote your favorites" queue, exchanged over the same
// `GroupSessionMessenger` as `PlaybackSyncMessage`, so it needs no new
// server/bridge involvement — it's peer-to-peer for the lifetime of the
// SharePlay session only, same as playback sync.
//
// Voter identity: `GroupSession.Participant.ID` isn't `Codable`, so instead
// each device mints and persists a random UUID (`localDeviceID`) the first
// time it's needed and includes that string in vote messages. It's scoped
// to this device, not this account, which is fine here — the only thing it
// guards against is a single device double-voting the same suggestion.

struct SharedQueueItem: Identifiable, Codable, Equatable {
    var id: String
    var sourceTrackID: String
    var title: String
    var artist: String
    var source: String
    var voterDeviceIDs: Set<String> = []
    var voteCount: Int { voterDeviceIDs.count }
}

private struct QueueSuggestMessage: Codable {
    var itemID: String
    var sourceTrackID: String
    var title: String
    var artist: String
    var source: String
    var suggestedByDeviceID: String
}

private struct QueueVoteMessage: Codable {
    var itemID: String
    var voterDeviceID: String
    var isUpvote: Bool
}

private struct QueueRemoveMessage: Codable {
    var itemID: String
}

extension SharePlayCoordinator {

    /// Stable per-device (not per-account) identity used only to dedupe this
    /// device's votes across a session — see file header.
    var localDeviceID: String {
        let key = "sharePlay.localDeviceID"
        if let existing = UserDefaults.standard.string(forKey: key) { return existing }
        let generated = UUID().uuidString
        UserDefaults.standard.set(generated, forKey: key)
        return generated
    }

    /// Queue sorted for display: most-voted first, ties broken by insertion order.
    var sortedSharedQueue: [SharedQueueItem] {
        sharedQueue.enumerated()
            .sorted { lhs, rhs in
                if lhs.element.voteCount != rhs.element.voteCount {
                    return lhs.element.voteCount > rhs.element.voteCount
                }
                return lhs.offset < rhs.offset
            }
            .map(\.element)
    }

    func subscribeQueueMessages(messenger: GroupSessionMessenger) {
        let suggestTask = Task { [weak self] in
            for await (message, _) in messenger.messages(of: QueueSuggestMessage.self) {
                await self?.applySuggest(message)
            }
        }
        let voteTask = Task { [weak self] in
            for await (message, _) in messenger.messages(of: QueueVoteMessage.self) {
                await self?.applyVote(message)
            }
        }
        let removeTask = Task { [weak self] in
            for await (message, _) in messenger.messages(of: QueueRemoveMessage.self) {
                await self?.applyRemove(message)
            }
        }
        tasks.append(contentsOf: [suggestTask, voteTask, removeTask])
    }

    // MARK: - Outgoing

    /// Adds `song` to the shared queue for every participant, with an
    /// automatic upvote from the suggester (mirrors how a suggestion always
    /// starts at 1 like on similar group-listening features elsewhere).
    func suggestTrack(_ song: Song) {
        guard isSessionActive, let messenger, let sourceTrackID = song.sourceTrackID else { return }
        guard !sharedQueue.contains(where: { $0.sourceTrackID == sourceTrackID }) else { return }
        let source = sourceTrackID.split(separator: ":", maxSplits: 1).first.map(String.init) ?? "youtube"
        let itemID = UUID().uuidString
        var item = SharedQueueItem(
            id: itemID, sourceTrackID: sourceTrackID, title: song.title,
            artist: song.artist, source: source
        )
        item.voterDeviceIDs.insert(localDeviceID)
        sharedQueue.append(item)

        let message = QueueSuggestMessage(
            itemID: itemID, sourceTrackID: sourceTrackID, title: song.title,
            artist: song.artist, source: source, suggestedByDeviceID: localDeviceID
        )
        Task { try? await messenger.send(message) }
    }

    /// Toggles the local device's vote on a suggestion.
    func toggleVote(for itemID: String) {
        guard isSessionActive, let messenger,
              let index = sharedQueue.firstIndex(where: { $0.id == itemID }) else { return }
        let isUpvote = !sharedQueue[index].voterDeviceIDs.contains(localDeviceID)
        if isUpvote {
            sharedQueue[index].voterDeviceIDs.insert(localDeviceID)
        } else {
            sharedQueue[index].voterDeviceIDs.remove(localDeviceID)
        }

        let message = QueueVoteMessage(itemID: itemID, voterDeviceID: localDeviceID, isUpvote: isUpvote)
        Task { try? await messenger.send(message) }
    }

    /// Resolves the highest-voted suggestion to a playable `Song` and
    /// inserts it as "Play Next" locally, then removes it from every
    /// participant's shared queue (each participant does their own
    /// resolve-and-insert when they tap this, same "resolve locally from
    /// an id rather than forward a URL" reasoning as `apply(message:)`
    /// above). No-op if there's nothing suggested or the track can't be
    /// resolved (e.g. a Bandcamp suggestion — see `apply(message:)`).
    func playTopSuggestion() async {
        guard let top = sortedSharedQueue.first, let streaming, let player else { return }
        guard top.source != "bandcamp" else { return }
        let idPart = top.sourceTrackID.split(separator: ":", maxSplits: 1).last.map(String.init) ?? ""
        let track = StreamTrack(
            id: idPart, title: top.title, artist: top.artist,
            durationSeconds: 0, thumbnailURL: "", source: top.source, youtubeURL: ""
        )
        guard let url = try? await streaming.streamURL(for: track) else { return }
        let song = streaming.toSong(track: track, streamURL: url)
        player.insertNext(song: song)
        removeFromQueue(itemID: top.id)
    }

    func removeFromQueue(itemID: String) {
        guard isSessionActive, let messenger else { return }
        sharedQueue.removeAll { $0.id == itemID }
        let message = QueueRemoveMessage(itemID: itemID)
        Task { try? await messenger.send(message) }
    }

    // MARK: - Incoming

    private func applySuggest(_ message: QueueSuggestMessage) {
        guard !sharedQueue.contains(where: { $0.id == message.itemID }) else { return }
        var item = SharedQueueItem(
            id: message.itemID, sourceTrackID: message.sourceTrackID, title: message.title,
            artist: message.artist, source: message.source
        )
        item.voterDeviceIDs.insert(message.suggestedByDeviceID)
        sharedQueue.append(item)
    }

    private func applyVote(_ message: QueueVoteMessage) {
        guard let index = sharedQueue.firstIndex(where: { $0.id == message.itemID }) else { return }
        if message.isUpvote {
            sharedQueue[index].voterDeviceIDs.insert(message.voterDeviceID)
        } else {
            sharedQueue[index].voterDeviceIDs.remove(message.voterDeviceID)
        }
    }

    private func applyRemove(_ message: QueueRemoveMessage) {
        sharedQueue.removeAll { $0.id == message.itemID }
    }
}
