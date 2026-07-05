import Foundation
import SwiftUI
import UIKit

extension AccountService {

    // MARK: - Folder structure backup (item 3)

    /// Schedules a push of the watched-folder structure 2 seconds after the
    /// last call. Called whenever watched folders or the library's imported
    /// songs change (folder added/removed, rescan picks up new files, etc.).
    func scheduleFolderBackupPush(folderService: MusicFolderService, library: LibraryManager) {
        guard isLoggedIn else { return }
        folderBackupDebounceTask?.cancel()
        folderBackupDebounceTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard let self, !Task.isCancelled, self.isLoggedIn else { return }
            await self.pushFolderBackups(folderService: folderService, library: library)
        }
    }

    /// Pushes the current watched-folder structure (relative paths under
    /// Documents + the tracks in each) to the server, replacing any previous
    /// folder backup wholesale. Fire-and-forget — failures are logged only.
    func pushFolderBackups(folderService: MusicFolderService, library: LibraryManager) async {
        guard isLoggedIn else { return }
        let entries = folderService.folderBackupEntries(songs: library.allSongs)
        struct Body: Encodable {
            let folders: [FolderBackupEntry]
            enum CodingKeys: String, CodingKey { case folders }
        }
        do {
            _ = try await makeRequest("/user/folder-backups", method: "PUT", body: Body(folders: entries))
            appLog("pushFolderBackups: pushed \(entries.count) folder(s)", category: "account")
        } catch let err as AccountError {
            appWarn("pushFolderBackups failed [\(err.statusCode)]: \(err.message)", category: "account")
        } catch {
            appWarn("pushFolderBackups error: \(error.localizedDescription)", category: "account")
        }
    }

    /// Fetches this account's backed-up folder structure, if any. Returns an
    /// empty array if the user never pushed one (never used watched folders, or
    /// hasn't synced since this feature shipped).
    func fetchFolderBackups() async -> [FolderBackupEntry] {
        guard isLoggedIn else { return [] }
        struct Response: Decodable {
            let folders: [FolderBackupEntry]
            enum CodingKeys: String, CodingKey { case folders }
        }
        do {
            let data = try await makeRequest("/user/folder-backups")
            let decoded = try JSONDecoder().decode(Response.self, from: data)
            return decoded.folders
        } catch let err as AccountError {
            appWarn("fetchFolderBackups failed [\(err.statusCode)]: \(err.message)", category: "account")
            return []
        } catch {
            appWarn("fetchFolderBackups error: \(error.localizedDescription)", category: "account")
            return []
        }
    }
}
