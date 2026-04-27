import AVFoundation
import Foundation

enum DocumentImportError: LocalizedError {
    case unreadableFile
    case copyFailed

    var errorDescription: String? {
        switch self {
        case .unreadableFile:
            return "The selected audio file could not be read."
        case .copyFailed:
            return "The audio file could not be copied into the app library."
        }
    }
}

struct DocumentImportService {
    private let supportedExtensions: Set<String> = [
        "mp3", "m4a", "aac", "wav", "aif", "aiff", "caf", "flac", "mp4"
    ]

    func importFiles(from urls: [URL]) async throws -> [Song] {
        var songs: [Song] = []
        for url in urls {
            if let song = try await importFile(from: url) {
                songs.append(song)
            }
        }
        return songs
    }

    private func importFile(from sourceURL: URL) async throws -> Song? {
        let didStartAccess = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if didStartAccess {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }

        guard supportedExtensions.contains(sourceURL.pathExtension.lowercased()) else {
            return nil
        }

        let destination = try destinationURL(for: sourceURL)
        let manager = FileManager.default

        do {
            if manager.fileExists(atPath: destination.path) {
                try manager.removeItem(at: destination)
            }
            try manager.copyItem(at: sourceURL, to: destination)
        } catch {
            throw DocumentImportError.copyFailed
        }

        return await makeSong(for: destination)
    }

    private func destinationURL(for sourceURL: URL) throws -> URL {
        let libraryDir = try FileManager.default.url(
            for: .documentDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ).appendingPathComponent("Imported Music", isDirectory: true)

        try FileManager.default.createDirectory(at: libraryDir, withIntermediateDirectories: true)

        let baseName = sourceURL.deletingPathExtension().lastPathComponent
        let ext = sourceURL.pathExtension
        let safeName = baseName
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")

        return libraryDir.appendingPathComponent("\(safeName).\(ext)")
    }

    private func makeSong(for url: URL) async -> Song {
        let asset = AVURLAsset(url: url)
        let loadedDuration = (try? await asset.load(.duration)).map(CMTimeGetSeconds) ?? 0
        let commonMetadata = (try? await asset.load(.commonMetadata)) ?? []
        let metadata = (try? await asset.load(.metadata)) ?? []
        var title = url.deletingPathExtension().lastPathComponent
        var artist = ""
        var album = ""
        var genre = ""

        for item in commonMetadata {
            switch item.commonKey?.rawValue {
            case "title":
                title = item.stringValue ?? title
            case "artist":
                artist = item.stringValue ?? artist
            case "albumName":
                album = item.stringValue ?? album
            default:
                break
            }
        }

        if let genreItem = metadata.first(where: { $0.identifier?.rawValue.lowercased().contains("genre") == true }) {
            genre = genreItem.stringValue ?? ""
        }

        return Song(
            title: title,
            artist: artist,
            album: album,
            duration: loadedDuration.isFinite ? loadedDuration : 0,
            url: url,
            artworkCacheKey: url.lastPathComponent,
            genre: genre
        )
    }
}
