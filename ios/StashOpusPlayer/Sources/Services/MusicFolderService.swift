import Foundation
import UIKit

@MainActor
final class MusicFolderService: ObservableObject {
    static let bookmarksKey = "music_folder_bookmarks_v1"

    @Published private(set) var watchedFolders: [WatchedFolder] = []

    struct WatchedFolder: Identifiable, Codable {
        let id: UUID
        var displayName: String
        var bookmarkData: Data
        var lastScannedAt: Date
        var trackCount: Int
    }

    init() { loadBookmarks() }

    // MARK: - Public API

    /// Add a folder from a URL obtained via .fileImporter / UIDocumentPickerViewController.
    func addFolder(url: URL) throws {
        // On iOS, startAccessingSecurityScopedResource() must be called before
        // creating a bookmark so the sandbox grants access.
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }

        // .minimalBookmark is the correct option on iOS (withSecurityScope is macOS-only).
        let bookmarkData = try url.bookmarkData(
            options: .minimalBookmark,
            includingResourceValuesForKeys: [.isDirectoryKey],
            relativeTo: nil
        )

        let folder = WatchedFolder(
            id: UUID(),
            displayName: url.lastPathComponent,
            bookmarkData: bookmarkData,
            lastScannedAt: Date(),
            trackCount: 0
        )

        guard !watchedFolders.contains(where: {
            $0.displayName == folder.displayName && $0.bookmarkData == folder.bookmarkData
        }) else { return }

        watchedFolders.append(folder)
        saveBookmarks()
    }

    func removeFolder(id: UUID) {
        watchedFolders.removeAll { $0.id == id }
        saveBookmarks()
    }

    func updateTrackCount(_ count: Int, for id: UUID) {
        guard let index = watchedFolders.firstIndex(where: { $0.id == id }) else { return }
        watchedFolders[index].trackCount = count
        watchedFolders[index].lastScannedAt = Date()
        saveBookmarks()
    }

    /// Resolve all persisted bookmarks and return valid accessible URLs.
    /// Each returned URL has `startAccessingSecurityScopedResource()` already called;
    /// callers must call `stopAccessingSecurityScopedResource()` when done.
    func resolveAll() -> [URL] {
        var valid: [URL] = []
        var staleIDs: [UUID] = []

        for folder in watchedFolders {
            var isStale = false
            // iOS: use no bookmark-resolution options (withSecurityScope is macOS-only)
            guard let resolved = try? URL(
                resolvingBookmarkData: folder.bookmarkData,
                options: [],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            ) else {
                staleIDs.append(folder.id)
                continue
            }

            if isStale {
                // Try to refresh the bookmark while we still have access.
                let didAccess = resolved.startAccessingSecurityScopedResource()
                let fresh = try? resolved.bookmarkData(
                    options: .minimalBookmark,
                    includingResourceValuesForKeys: nil,
                    relativeTo: nil
                )
                if didAccess { resolved.stopAccessingSecurityScopedResource() }

                if let fresh, let idx = watchedFolders.firstIndex(where: { $0.id == folder.id }) {
                    watchedFolders[idx].bookmarkData = fresh
                    saveBookmarks()
                } else {
                    staleIDs.append(folder.id)
                    continue
                }
            }

            // The resolved URL is a security-scoped resource; start access for the caller.
            if resolved.startAccessingSecurityScopedResource() {
                valid.append(resolved)
            }
            // If startAccessing returns false the URL is still valid but may not need
            // explicit access (e.g. it's within our sandbox already).
            else {
                valid.append(resolved)
            }
        }

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
              let decoded = try? JSONDecoder().decode([WatchedFolder].self, from: data)
        else { return }
        watchedFolders = decoded
    }
}
