import Foundation

// MARK: - AriaAction

/// One action Aria Lumi took on an existing track — currently just
/// `duplicateRemoved` (see `DuplicateFinderService.refineGroupsWithAria`).
/// Local-only record: it exists so the surviving track's context menu can
/// offer "Revert Aria's Change" and so the toast shown right after the
/// action has something to describe. The durable audit trail lives
/// server-side in `ios_aria_actions` (see `AccountService.reportAriaAction`);
/// this is the on-device pointer back to what's actually revertible on
/// THIS device (the trashed file only exists here).
struct AriaAction: Codable, Identifiable, Equatable {
    enum Kind: String, Codable {
        case duplicateRemoved
        case corruptFileDeleted
        case cloudTrackRemoved
        case deadLinkHealed
    }

    let id: UUID
    /// The song whose context menu should offer to revert this action —
    /// for `duplicateRemoved`, the copy that was kept.
    let survivingSongID: String
    let kind: Kind
    let title: String
    let artist: String
    /// `RecentlyDeletedService.Entry.id` for the removed copy — how revert
    /// finds the trashed file to restore.
    let removedEntryID: String
    /// Server-assigned `ios_aria_actions.id`, if the report succeeded —
    /// used to mark the action reverted server-side too. `nil` just means
    /// the audit-log write failed; the local revert still works fully
    /// without it.
    var serverActionID: Int?
    let confidence: String
    let timestamp: Date
    var reverted: Bool = false
}

// MARK: - AriaActivityLog

/// Local ledger of what Aria Lumi has actually done to the library (as
/// opposed to `IntelligenceSuggestionCache`, which tracks metadata picks
/// she only suggested). Keeps the last 200 actions, same persistence
/// pattern as `RecentlyDeletedService`. Drives the "Aria touched this
/// track" toast and the long-press "Revert Aria's Change" menu item.
@MainActor
final class AriaActivityLog: ObservableObject {
    static let shared = AriaActivityLog()

    @Published private(set) var actions: [AriaAction] = []

    private static let maxEntries = 200
    private enum Keys {
        static let actions = "aria_activity_log_v1"
    }

    private init() {
        if let data = UserDefaults.standard.data(forKey: Keys.actions),
           let decoded = try? JSONDecoder().decode([AriaAction].self, from: data) {
            actions = decoded
        }
    }

    /// The most recent un-reverted action affecting `songID`, if any —
    /// used by `SongContextMenuContent` to decide whether to show the
    /// revert item.
    func activeAction(forSurvivingSongID songID: String) -> AriaAction? {
        actions.last { $0.survivingSongID == songID && !$0.reverted }
    }

    /// Records a duplicate-removal action, toasts it, and reports it to the
    /// server for the deep audit log. Called right after the local trash
    /// operation already succeeded — this never performs the removal itself.
    func recordDuplicateRemoved(
        survivingSongID: String, title: String, artist: String,
        removedEntryID: String, confidence: String, memoryID: Int?
    ) {
        let localID = UUID()
        var action = AriaAction(
            id: localID, survivingSongID: survivingSongID, kind: .duplicateRemoved,
            title: title, artist: artist, removedEntryID: removedEntryID,
            serverActionID: nil, confidence: confidence, timestamp: Date()
        )
        actions.append(action)
        trimAndPersist()

        ToastCenter.shared.show(
            "Aria removed a duplicate of \"\(title)\"", category: .info, icon: "sparkles"
        )

        Task { [weak self] in
            let serverID = await AccountService.shared?.reportAriaAction(
                type: "duplicate_removed", title: title, artist: artist,
                detail: "Auto-removed a lower-quality duplicate copy; kept this one.",
                after: ["kept_song_id": survivingSongID],
                confidence: confidence, memoryID: memoryID
            )
            guard let self, let serverID else { return }
            if let index = self.actions.firstIndex(where: { $0.id == localID }) {
                self.actions[index].serverActionID = serverID
                self.persist()
            }
        }
    }

    /// Reverts a duplicate-removal action: restores the trashed copy via
    /// `RecentlyDeletedService` and re-adds it to the library. Best-effort
    /// on the server report — the local restore already happened by the
    /// time that call goes out, so its failure doesn't get surfaced.
    func revertDuplicateRemoved(_ action: AriaAction, library: LibraryManager) {
        guard let index = actions.firstIndex(where: { $0.id == action.id }), !actions[index].reverted else { return }
        guard let restored = RecentlyDeletedService.shared?.restore(entryID: action.removedEntryID) else {
            ToastCenter.shared.show("Couldn't restore \"\(action.title)\" — it may have been permanently deleted since", category: .error)
            return
        }
        library.readdRestoredSong(restored)
        actions[index].reverted = true
        persist()
        ToastCenter.shared.show("Restored \"\(action.title)\"", category: .success, icon: "arrow.uturn.backward")

        if let serverID = action.serverActionID {
            Task { await AccountService.shared?.reportAriaActionReverted(actionID: serverID) }
        }
    }

    /// Records Aria Lumi's autonomous corrupt-file cleanup (see
    /// `CorruptFileFinderService.ariaAutoDeleteCorruptFiles`), toasts it, and
    /// reports each removal to the server audit log. Unlike
    /// `recordDuplicateRemoved`, there's no surviving row left to hang a
    /// "Revert Aria's Change" context-menu item off of — the file is simply
    /// gone from the library — but it's not gone from disk: the removal
    /// itself went through `RecentlyDeletedService`/the Files app Trash
    /// (see `LibraryManager.ariaRemoveCorruptFile`), so it's still fully
    /// recoverable there, same revertibility guarantee, different UI.
    func logCorruptFilesDeleted(_ entries: [CorruptFileEntry]) {
        guard !entries.isEmpty else { return }
        for entry in entries {
            actions.append(AriaAction(
                id: UUID(), survivingSongID: "", kind: .corruptFileDeleted,
                title: entry.fileName, artist: "", removedEntryID: entry.id.uuidString,
                serverActionID: nil, confidence: "high", timestamp: Date()
            ))
            Task {
                _ = await AccountService.shared?.reportAriaAction(
                    type: "corrupt_file_deleted", title: entry.fileName, artist: nil,
                    detail: entry.reasonText, after: nil, confidence: "high", memoryID: nil
                )
            }
        }
        trimAndPersist()
    }

    /// Records Aria Lumi's cloud-library cleanup (see
    /// `AccountService.ariaCloudCleanup`) and toasts it. The server has
    /// already made the removal by the time this is called — this is a
    /// local record only (no server report round-trip needed, unlike the
    /// on-device actions above, since the server wrote its own
    /// `ios_aria_actions` row directly). No revert: these rows never
    /// pointed at real audio to begin with.
    func logCloudTracksRemoved(_ entries: [(filename: String, title: String)]) {
        guard !entries.isEmpty else { return }
        for entry in entries {
            actions.append(AriaAction(
                id: UUID(), survivingSongID: "", kind: .cloudTrackRemoved,
                title: entry.title, artist: "", removedEntryID: entry.filename,
                serverActionID: nil, confidence: "high", timestamp: Date()
            ))
        }
        trimAndPersist()
        let word = entries.count == 1 ? "entry" : "entries"
        ToastCenter.shared.show("Aria cleaned up \(entries.count) broken cloud \(word)", category: .info, icon: "sparkles")
    }

    /// Records Aria Lumi silently relinking a track whose upstream source
    /// went dead (see `DeadLinkHealingService`) and toasts it. This
    /// automation already existed and already ran on its own — it just
    /// never told the user it happened, logging only to the debug console.
    /// No revert: relinking only changes which source a FUTURE re-download
    /// would use, never the current (already playable) local file, so
    /// there's nothing here that needs undoing.
    func logDeadLinkHealed(title: String, artist: String) {
        actions.append(AriaAction(
            id: UUID(), survivingSongID: "", kind: .deadLinkHealed,
            title: title, artist: artist, removedEntryID: "",
            serverActionID: nil, confidence: "high", timestamp: Date()
        ))
        trimAndPersist()
        ToastCenter.shared.show("Aria relinked \"\(title)\" to a working source", category: .info, icon: "sparkles")
    }

    private func trimAndPersist() {
        if actions.count > Self.maxEntries {
            actions.removeFirst(actions.count - Self.maxEntries)
        }
        persist()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(actions) {
            UserDefaults.standard.set(data, forKey: Keys.actions)
        }
    }
}
