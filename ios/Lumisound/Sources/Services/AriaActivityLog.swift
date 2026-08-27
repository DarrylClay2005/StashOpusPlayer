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
