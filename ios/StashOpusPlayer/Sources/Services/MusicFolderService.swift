import Foundation
import UIKit

@MainActor
final class MusicFolderService: ObservableObject {
    static let bookmarksKey = "music_folder_bookmarks_v1"

    @Published private(set) var watchedFolders: [WatchedFolder] = []

    struct WatchedFolder: Identifiable, Codable {
        let id: UUID
        var displayName: String   // last path component
        var bookmarkData: Data    // security-scoped bookmark
        var lastScannedAt: Date
        var trackCount: Int
    }

    init() {
        loadBookmarks()
    }

    // MARK: - Public API

    /// Add a folder from a security-scoped URL (from UIDocumentPickerViewController / .fileImporter).
    func addFolder(url: URL) throws {
        // Start accessing so we can create the bookmark.
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }

        let bookmarkData = try url.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )

        let folder = WatchedFolder(
            id: UUID(),
            displayName: url.lastPathComponent,
            bookmarkData: bookmarkData,
            lastScannedAt: Date(),
            trackCount: 0
        )

        // Avoid duplicates by display name + bookmark data comparison.
        guard !watchedFolders.contains(where: { $0.displayName == folder.displayName && $0.bookmarkData == folder.bookmarkData }) else {
            return
        }

        watchedFolders.append(folder)
        saveBookmarks()
    }

    /// Remove a watched folder by ID.
    func removeFolder(id: UUID) {
        watchedFolders.removeAll { $0.id == id }
        saveBookmarks()
    }

    /// Update the track count for a folder after a scan.
    func updateTrackCount(_ count: Int, for id: UUID) {
        guard let index = watchedFolders.firstIndex(where: { $0.id == id }) else { return }
        watchedFolders[index].trackCount = count
        watchedFolders[index].lastScannedAt = Date()
        saveBookmarks()
    }

    /// Resolve all bookmarks and return valid (already-accessed) URLs.
    /// Callers must call `stopAccessingSecurityScopedResource()` on each URL when done.
    func resolveAll() -> [URL] {
        var valid: [URL] = []
        var staleIDs: [UUID] = []

        for folder in watchedFolders {
            var isStale = false
            guard let resolvedURL = try? URL(
                resolvingBookmarkData: folder.bookmarkData,
                options: .withSecurityScope,
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            ) else {
                staleIDs.append(folder.id)
                continue
            }

            if isStale {
                // Attempt to refresh the bookmark.
                let accessing = resolvedURL.startAccessingSecurityScopedResource()
                defer { if accessing { resolvedURL.stopAccessingSecurityScopedResource() } }
                if let fresh = try? resolvedURL.bookmarkData(
                    options: .withSecurityScope,
                    includingResourceValuesForKeys: nil,
                    relativeTo: nil
                ), let index = watchedFolders.firstIndex(where: { $0.id == folder.id }) {
                    watchedFolders[index].bookmarkData = fresh
                    saveBookmarks()
                } else {
                    staleIDs.append(folder.id)
                    continue
                }
            }

            if resolvedURL.startAccessingSecurityScopedResource() {
                valid.append(resolvedURL)
            } else {
                staleIDs.append(folder.id)
            }
        }

        // Remove permanently stale entries.
        if !staleIDs.isEmpty {
            watchedFolders.removeAll { staleIDs.contains($0.id) }
            saveBookmarks()
        }

        return valid
    }

    // MARK: - Persistence

    private func saveBookmarks() {
        if let encoded = try? JSONEncoder().encode(watchedFolders) {
            UserDefaults.standard.set(encoded, forKey: Self.bookmarksKey)
        }
    }

    private func loadBookmarks() {
        guard let data = UserDefaults.standard.data(forKey: Self.bookmarksKey),
              let decoded = try? JSONDecoder().decode([WatchedFolder].self, from: data) else {
            return
        }
        watchedFolders = decoded
    }
}
