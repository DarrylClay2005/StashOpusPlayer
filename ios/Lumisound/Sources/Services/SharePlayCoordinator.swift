import GroupActivities
import Combine
import Foundation

/// Message exchanged between SharePlay participants over the session's
/// `GroupSessionMessenger`. `sourceTrackID` is the same "source:id" string as
/// `Song.sourceTrackID` (e.g. "youtube:dQw4w9WgXcQ") — each participant
/// independently re-resolves a playable stream URL for that id via their own
/// `StreamingService.streamURL(for:)` rather than one device sending the other
/// a URL directly (bridge stream-proxy URLs are single-request/short-lived,
/// so forwarding one wouldn't reliably play on a second device anyway).
struct PlaybackSyncMessage: Codable {
    var sourceTrackID: String
    var title: String
    var artist: String
    var source: String
    var isPlaying: Bool
    var positionSeconds: TimeInterval
    /// `Date().timeIntervalSince1970` at send time, used on receipt to account
    /// for the time the message spent in flight — see `adjustedPosition`.
    var sentAt: TimeInterval

    /// `positionSeconds` compensated for message transit time, so a receiving
    /// device that applies this a second or two after it was sent doesn't
    /// start noticeably behind. Not frame-accurate — see `ListenTogetherActivity`'s
    /// doc comment for why exact sync isn't attempted.
    var adjustedPosition: TimeInterval {
        guard isPlaying else { return positionSeconds }
        let elapsed = Date().timeIntervalSince1970 - sentAt
        return positionSeconds + max(0, elapsed)
    }
}

/// Owns the SharePlay `GroupSession` lifecycle for `ListenTogetherActivity` and
/// keeps `AudioPlayerManager` roughly in sync across participants by exchanging
/// `PlaybackSyncMessage`s. Wired up as a weak `.shared` singleton (same pattern
/// as `AudioPlayerManager`/`LibraryManager`/etc.) and given weak references to
/// the live player/library/streaming service by `LumisoundApp` at launch,
/// since — like App Intents — this needs to reach app state without being a
/// SwiftUI environment object itself.
@MainActor
final class SharePlayCoordinator: ObservableObject {
    static weak var shared: SharePlayCoordinator?

    @Published private(set) var isSessionActive = false
    @Published private(set) var participantCount = 0

    weak var player: AudioPlayerManager?
    weak var library: LibraryManager?
    weak var streaming: StreamingService?

    private var groupSession: GroupSession<ListenTogetherActivity>?
    private var messenger: GroupSessionMessenger?
    private var subscriptions = Set<AnyCancellable>()
    private var tasks: [Task<Void, Never>] = []

    /// Set while applying an incoming message to the local player, so the
    /// resulting `currentSong`/`isPlaying` change doesn't get re-broadcast
    /// straight back to the group (which would otherwise loop messages
    /// between participants forever).
    private var isApplyingRemoteMessage = false

    init() {
        Self.shared = self
        let sessionTask = Task { [weak self] in
            for await session in ListenTogetherActivity.sessions() {
                self?.configure(session: session)
            }
        }
        tasks.append(sessionTask)
    }

    deinit {
        for task in tasks { task.cancel() }
    }

    // MARK: - Session lifecycle

    private func configure(session: GroupSession<ListenTogetherActivity>) {
        groupSession = session
        let messenger = GroupSessionMessenger(session: session)
        self.messenger = messenger

        session.$state
            .sink { [weak self] state in
                if case .invalidated = state {
                    self?.tearDown()
                }
            }
            .store(in: &subscriptions)

        session.$activeParticipants
            .sink { [weak self] participants in
                self?.participantCount = participants.count
            }
            .store(in: &subscriptions)

        let messageTask = Task { [weak self] in
            for await (message, _) in messenger.messages(of: PlaybackSyncMessage.self) {
                await self?.apply(message: message)
            }
        }
        tasks.append(messageTask)

        session.join()
        isSessionActive = true

        // Bring the newly-joined participant up to date immediately with
        // whatever's currently playing locally, rather than waiting for the
        // next natural play/pause/track-change to broadcast.
        if let song = player?.currentSong {
            broadcastTrackChange(song: song, isPlaying: player?.isPlaying ?? false, position: player?.position ?? 0)
        }
    }

    private func tearDown() {
        groupSession = nil
        messenger = nil
        isSessionActive = false
        participantCount = 0
        subscriptions.removeAll()
    }

    /// Ends the current SharePlay session for this participant (does not end it
    /// for the others — matches how leaving a FaceTime SharePlay session works).
    func leaveSession() {
        groupSession?.leave()
        tearDown()
    }

    // MARK: - Outgoing

    func broadcastTrackChange(song: Song?, isPlaying: Bool, position: TimeInterval) {
        broadcast(song: song, isPlaying: isPlaying, position: position)
    }

    func broadcastPlayState(isPlaying: Bool, position: TimeInterval) {
        broadcast(song: player?.currentSong, isPlaying: isPlaying, position: position)
    }

    private func broadcast(song: Song?, isPlaying: Bool, position: TimeInterval) {
        guard isSessionActive, !isApplyingRemoteMessage else { return }
        guard let messenger, let song, let sourceTrackID = song.sourceTrackID else { return }
        // "source:id" — see Song.sourceTrackID's doc comment for the format.
        let source = sourceTrackID.split(separator: ":", maxSplits: 1).first.map(String.init) ?? "youtube"
        let message = PlaybackSyncMessage(
            sourceTrackID: sourceTrackID,
            title: song.title,
            artist: song.artist,
            source: source,
            isPlaying: isPlaying,
            positionSeconds: position,
            sentAt: Date().timeIntervalSince1970
        )
        Task { try? await messenger.send(message) }
    }

    // MARK: - Incoming

    private func apply(message: PlaybackSyncMessage) async {
        guard let player, let streaming else { return }
        isApplyingRemoteMessage = true
        defer { isApplyingRemoteMessage = false }

        if player.currentSong?.sourceTrackID != message.sourceTrackID {
            // Only YouTube/SoundCloud sources can be re-resolved from just an id —
            // Bandcamp's stream lookup additionally needs the original webpage
            // URL (see StreamingService.streamURL(for:)), which isn't carried by
            // Song.sourceTrackID, so a Bandcamp track played by another
            // participant can't be joined this way. Rare in practice (Bandcamp
            // has no search extractor to begin with) but worth the guard.
            guard message.source != "bandcamp" else { return }
            let idPart = message.sourceTrackID.split(separator: ":", maxSplits: 1).last.map(String.init) ?? ""
            let track = StreamTrack(
                id: idPart,
                title: message.title,
                artist: message.artist,
                durationSeconds: 0,
                thumbnailURL: "",
                source: message.source,
                youtubeURL: ""
            )
            guard let url = try? await streaming.streamURL(for: track) else { return }
            let song = streaming.toSong(track: track, streamURL: url)
            player.setQueue([song], startIndex: 0, autoplay: message.isPlaying)
            if message.isPlaying {
                player.seek(to: message.adjustedPosition)
            }
            return
        }

        // Same track already loaded — just reconcile play state and, if the
        // drift from the sender's reported position is large enough to notice,
        // seek to catch up.
        if player.isPlaying != message.isPlaying {
            player.togglePlayPause()
        }
        if abs(player.position - message.adjustedPosition) > 2 {
            player.seek(to: message.adjustedPosition)
        }
    }
}
