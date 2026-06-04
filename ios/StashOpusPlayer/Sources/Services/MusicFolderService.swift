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
        appLog("addFolder: \(url.lastPathComponent)", category: "library")
        // On iOS, startAccessingSecurityScopedResource() must be called before
        // creating a bookmark so the sandbox grants access.
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }

        // .minimalBookmark is the correct option on iOS (withSecurityScope is macOS-only).
        let bookmarkData: Data
        do {
            bookmarkData = try url.bookmarkData(
                options: .minimalBookmark,
                includingResourceValuesForKeys: [.isDirectoryKey],
                relativeTo: nil
            )
        } catch {
            appError("addFolder bookmark creation failed for \(url.lastPathComponent): \(error)", category: "library")
            throw error
        }

        let folder = WatchedFolder(
            id: UUID(),
            displayName: url.lastPathComponent,
            bookmarkData: bookmarkData,
            lastScannedAt: Date(),
            trackCount: 0
        )

        guard !watchedFolders.contains(where: {
            $0.displayName == folder.displayName && $0.bookmarkData == folder.bookmarkData
        }) else {
            appLog("addFolder: skipped duplicate \(url.lastPathComponent)", category: "library")
            return
        }

        watchedFolders.append(folder)
        saveBookmarks()
        appLog("addFolder: added \(url.lastPathComponent) (total: \(watchedFolders.count))", category: "library")
    }

    func removeFolder(id: UUID) {
        let name = watchedFolders.first(where: { $0.id == id })?.displayName ?? id.uuidString
        watchedFolders.removeAll { $0.id == id }
        saveBookmarks()
        appLog("removeFolder: removed \(name)", category: "library")
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
        appLog("resolveAll: resolving \(watchedFolders.count) folder bookmark(s)", category: "library")
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
                appWarn("resolveAll: bookmark resolution failed for \(folder.displayName) — marking stale", category: "library")
                staleIDs.append(folder.id)
                continue
            }

            if isStale {
                appLog("resolveAll: stale bookmark for \(folder.displayName), attempting refresh", category: "library")
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
                    appLog("resolveAll: refreshed bookmark for \(folder.displayName)", category: "library")
                } else {
                    appWarn("resolveAll: could not refresh bookmark for \(folder.displayName) — removing", category: "library")
                    staleIDs.append(folder.id)
                    continue
                }
            }

            // Call startAccessingSecurityScopedResource() regardless — it's a no-op for
            // URLs already within the app's sandbox, and activates access for out-of-sandbox
            // URLs obtained via document picker. Only exclude the URL if it doesn't exist.
            _ = resolved.startAccessingSecurityScopedResource()
            if FileManager.default.fileExists(atPath: resolved.path) {
                valid.append(resolved)
            } else {
                appWarn("resolveAll: path no longer exists for \(folder.displayName)", category: "library")
                staleIDs.append(folder.id)
            }
        }

        if !staleIDs.isEmpty {
            appWarn("resolveAll: removing \(staleIDs.count) stale folder(s)", category: "library")
            watchedFolders.removeAll { staleIDs.contains($0.id) }
            saveBookmarks()
        }
        appLog("resolveAll: \(valid.count)/\(watchedFolders.count + staleIDs.count) folders resolved", category: "library")
        return valid
    }

    // MARK: - Persistence

    private func saveBookmarks() {
        do {
            UserDefaults.standard.set(try JSONEncoder().encode(watchedFolders), forKey: Self.bookmarksKey)
        } catch {
            appError("saveBookmarks encode failed: \(error)", category: "library")
        }
    }

    private func loadBookmarks() {
        guard let data = UserDefaults.standard.data(forKey: Self.bookmarksKey) else { return }
        do {
            watchedFolders = try JSONDecoder().decode([WatchedFolder].self, from: data)
            appLog("loadBookmarks: restored \(watchedFolders.count) folder(s)", category: "library")
        } catch {
            appError("loadBookmarks decode failed: \(error)", category: "library")
        }
    }
}
