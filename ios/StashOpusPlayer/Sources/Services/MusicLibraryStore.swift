import Foundation
import MediaPlayer
import UniformTypeIdentifiers

@MainActor
final class MusicLibraryStore: ObservableObject {
    @Published private(set) var authorizationStatus: MPMediaLibraryAuthorizationStatus = MPMediaLibrary.authorizationStatus()
    @Published private(set) var songs: [Song] = []
    @Published private(set) var importedSongs: [Song] = []
    @Published private(set) var isScanning = false
    @Published var errorMessage: String?

    private let importer = DocumentImportService()

    var allSongs: [Song] {
        (songs + importedSongs).sorted {
            $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
        }
    }

    var artists: [String] {
        Array(Set(allSongs.map(\.artistName))).sorted()
    }

    var albums: [String] {
        Array(Set(allSongs.map(\.albumName))).sorted()
    }

    func requestAccessAndScan() {
        Task {
            let status = await MPMediaLibrary.requestAuthorization()
            authorizationStatus = status
            if status == .authorized {
                scanMediaLibrary()
            } else {
                errorMessage = "Media library access is required to scan Apple Music library items. Imported files still work."
            }
        }
    }

    func scanMediaLibrary() {
        guard authorizationStatus == .authorized else {
            requestAccessAndScan()
            return
        }

        isScanning = true
        errorMessage = nil

        Task.detached(priority: .userInitiated) {
            let query = MPMediaQuery.songs()
            let items = query.items ?? []
            let scanned = items.compactMap(Song.init(mediaItem:))
                .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }

            await MainActor.run {
                self.songs = scanned
                self.isScanning = false
            }
        }
    }

    func importFiles(urls: [URL]) {
        guard !urls.isEmpty else { return }
        isScanning = true
        errorMessage = nil

        Task {
            do {
                let imported = try await importer.importFiles(from: urls)
                importedSongs.append(contentsOf: imported)
                importedSongs = Array(Dictionary(grouping: importedSongs, by: \.id).compactMap { $0.value.first })
            } catch {
                errorMessage = error.localizedDescription
            }
            isScanning = false
        }
    }
}
