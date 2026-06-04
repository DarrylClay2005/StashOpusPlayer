import AVFoundation
import Foundation
import UIKit

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
    static let supportedExtensions: Set<String> = [
        "mp3", "m4a", "aac", "wav", "aif", "aiff", "caf", "flac", "mp4", "opus",
        "m4v", "mov"  // video containers with audio tracks
    ]
    private var supportedExtensions: Set<String> { Self.supportedExtensions }

    func importFiles(from urls: [URL]) async throws -> [Song] {
        // Import up to 4 files concurrently to avoid overloading the filesystem
        // while still gaining a meaningful throughput win on large batches.
        let maxConcurrency = 4
        var songs: [Song] = []

        try await withThrowingTaskGroup(of: Song?.self) { group in
            var inFlight = 0

            for url in urls {
                // Throttle: wait for one slot to free before adding another task
                if inFlight >= maxConcurrency {
                    if let song = try await group.next() {
                        if let song { songs.append(song) }
                        inFlight -= 1
                    }
                }

                group.addTask {
                    try await self.importFile(from: url)
                }
                inFlight += 1
            }

            // Drain remaining tasks
            for try await song in group {
                if let song { songs.append(song) }
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

        // If the destination already exists with the same byte size as the source,
        // the file is already fully imported — skip the redundant copy and just
        // return a Song built from the existing destination file.
        if manager.fileExists(atPath: destination.path) {
            let srcSize = (try? manager.attributesOfItem(atPath: sourceURL.path))?[.size] as? Int
            let dstSize = (try? manager.attributesOfItem(atPath: destination.path))?[.size] as? Int
            if let srcSize, let dstSize, srcSize == dstSize {
                return await makeSong(for: destination)
            }
            // Sizes differ (partial or updated file) — remove and re-copy.
            do {
                try manager.removeItem(at: destination)
            } catch {
                throw DocumentImportError.copyFailed
            }
        }

        do {
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

    /// Exposed so LibraryManager can build Song objects when scanning the Documents folder directly.
    func makeSong(for url: URL) async -> Song {
        let asset = AVURLAsset(url: url)
        let loadedDuration = (try? await asset.load(.duration)).map(CMTimeGetSeconds) ?? 0
        let commonMetadata = (try? await asset.load(.commonMetadata)) ?? []
        let metadata = (try? await asset.load(.metadata)) ?? []

        var title = url.deletingPathExtension().lastPathComponent
        var artist = ""
        var album = ""
        var genre = ""
        var trackNumber = 0
        var year = ""

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

        // Scan all metadata (covers ID3, iTunes atoms, etc.) for fields not
        // available through the common key set.
        for item in metadata {
            let idRaw = item.identifier?.rawValue.lowercased() ?? ""

            if genre.isEmpty, idRaw.contains("genre") {
                genre = item.stringValue ?? genre
            }

            // Track number — present as e.g. "tracknumber", "track", "itunes/tracknumber"
            if trackNumber == 0, idRaw.contains("tracknumber") || idRaw.hasSuffix("/track") {
                if let raw = item.stringValue {
                    // ID3 TRCK can be "5/12" — take the part before the slash
                    let part = raw.split(separator: "/").first.map(String.init) ?? raw
                    trackNumber = Int(part.trimmingCharacters(in: .whitespaces)) ?? 0
                } else if let num = try? await item.load(.numberValue) {
                    trackNumber = num.intValue
                }
            }

            // Year — present as "year", "date", "recordingyear" depending on format
            if year.isEmpty,
               idRaw.contains("year") || idRaw.contains("date") || idRaw.contains("recordingyear")
            {
                if let raw = item.stringValue {
                    // ISO 8601 date strings like "2003-11-06" — keep only the year portion
                    year = String(raw.prefix(4))
                } else if let num = try? await item.load(.numberValue) {
                    year = "\(num.intValue)"
                }
            }
        }

        // Extract audio technical properties via AVAudioFile, which is the
        // simplest way to get sampleRate without decoding format descriptions.
        var sampleRate = 0
        var bitrate = 0

        if let audioFile = try? AVAudioFile(forReading: url) {
            let rate = audioFile.processingFormat.sampleRate
            if rate > 0 { sampleRate = Int(rate.rounded()) }
        }

        // Bitrate lives in the audio track's format description (kCMFormatDescriptionExtension_VerbatimSampleDescription
        // or the audio stream basic description bitrate field is not always populated).
        // The most reliable cross-format path is through AVAssetTrack's estimatedDataRate.
        let audioTracks = try? await asset.loadTracks(withMediaType: .audio)
        if let track = audioTracks?.first,
           let estimatedRate = try? await track.load(.estimatedDataRate),
           estimatedRate > 0
        {
            bitrate = Int((estimatedRate / 1000).rounded())   // store as kbps
        }

        // Opus/Ogg files: AVFoundation does not parse Vorbis comments from the Ogg container.
        // As a fallback, read the OpusTags packet directly from the binary file.
        let fileExt = url.pathExtension.lowercased()
        let opusExtensions: Set<String> = ["opus", "ogg"]
        if opusExtensions.contains(fileExt), title == url.deletingPathExtension().lastPathComponent {
            let vorbis = Self.readVorbisComments(url: url)
            if let v = vorbis["TITLE"],  !v.isEmpty { title  = v }
            if let v = vorbis["ARTIST"], !v.isEmpty { artist = v }
            if let v = vorbis["ALBUM"],  !v.isEmpty { album  = v }
            if let v = vorbis["GENRE"],  !v.isEmpty { genre  = v }
            if let v = vorbis["DATE"] ?? vorbis["YEAR"], !v.isEmpty { year = String(v.prefix(4)) }
            if trackNumber == 0, let v = vorbis["TRACKNUMBER"] ?? vorbis["TRACK"], !v.isEmpty {
                trackNumber = Int(v.split(separator: "/").first.map(String.init) ?? v) ?? 0
            }
        }

        // Filename fallback: if title is still the raw filename, try "Artist - Title" pattern
        if title == url.deletingPathExtension().lastPathComponent && title.contains(" - ") {
            let parts = title.components(separatedBy: " - ")
            if parts.count >= 2 {
                if artist.isEmpty { artist = parts[0].trimmingCharacters(in: .whitespaces) }
                title = parts.dropFirst().joined(separator: " - ").trimmingCharacters(in: .whitespaces)
            }
        }

        // For video files (.mp4, .m4v, .mov), extract the first video frame as artwork
        // and cache it so ArtworkService can find it by filename key.
        let videoExtensions: Set<String> = ["mp4", "m4v", "mov"]
        // fileExt already declared above for the opus check
        if videoExtensions.contains(fileExt) {
            let assetForThumb = AVURLAsset(url: url)
            let generator = AVAssetImageGenerator(asset: assetForThumb)
            generator.appliesPreferredTrackTransform = true
            let time = CMTime(seconds: 1, preferredTimescale: 600)
            if let cgImage = try? generator.copyCGImage(at: time, actualTime: nil) {
                let thumbImage = UIImage(cgImage: cgImage)
                let thumbKey = url.lastPathComponent
                ArtworkService.shared.cacheImage(thumbImage, forKey: thumbKey)
            }
        }

        return Song(
            title: title,
            artist: artist,
            album: album,
            duration: loadedDuration.isFinite ? loadedDuration : 0,
            url: url,
            artworkCacheKey: url.lastPathComponent,
            trackNumber: trackNumber,
            year: year,
            genre: genre,
            bitrate: bitrate,
            sampleRate: sampleRate
        )
    }

    // MARK: - Vorbis comment binary parser

    /// Reads Vorbis comments directly from the binary data of an Opus (Ogg) file.
    ///
    /// AVFoundation does not expose Vorbis comments for .opus/.ogg files through the
    /// standard `AVURLAsset.commonMetadata` or `.metadata` APIs. The OpusTags packet
    /// lives in the SECOND Ogg page of the stream and has a simple binary format:
    ///   "OpusTags" magic | vendor string (length + UTF-8) | user comment list
    /// Each user comment is a "KEY=VALUE" UTF-8 string preceded by its 4-byte LE length.
    static func readVorbisComments(url: URL) -> [String: String] {
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe),
              data.count > 60 else { return [:] }
        let bytes = data

        // Walk Ogg pages; we want the SECOND one (OpusTags)
        var offset = 0
        var pageIndex = 0

        while offset + 27 < bytes.count {
            // Verify OggS capture pattern
            guard bytes[offset] == 0x4F, bytes[offset+1] == 0x67,
                  bytes[offset+2] == 0x67, bytes[offset+3] == 0x53 else { break }

            let segCount = Int(bytes[offset + 26])
            let headerSize = 27 + segCount
            guard offset + headerSize <= bytes.count else { break }

            // Sum segment sizes to find page data length
            var pageDataLen = 0
            for i in 0..<segCount { pageDataLen += Int(bytes[offset + 27 + i]) }

            let dataStart = offset + headerSize
            guard dataStart + pageDataLen <= bytes.count else { break }

            pageIndex += 1
            if pageIndex == 2 {
                // OpusTags magic
                let magic = [UInt8]("OpusTags".utf8)
                guard pageDataLen >= 8,
                      bytes[dataStart..<(dataStart+8)].elementsEqual(magic) else { break }

                var pos = dataStart + 8

                // Skip vendor string
                guard pos + 4 <= bytes.count else { break }
                let vendorLen = le32(bytes, pos); pos += 4
                pos += vendorLen

                // Comment count
                guard pos + 4 <= bytes.count else { break }
                let count = le32(bytes, pos); pos += 4

                var result: [String: String] = [:]
                for _ in 0..<min(count, 200) {
                    guard pos + 4 <= bytes.count else { break }
                    let cLen = le32(bytes, pos); pos += 4
                    guard cLen > 0, pos + cLen <= bytes.count else { pos += cLen; continue }
                    if let str = String(bytes: bytes[pos..<(pos+cLen)], encoding: .utf8),
                       let eq = str.firstIndex(of: "=") {
                        let key   = String(str[str.startIndex..<eq]).uppercased()
                        let value = String(str[str.index(after: eq)...])
                        result[key] = value
                    }
                    pos += cLen
                }
                return result
            }

            offset = dataStart + pageDataLen
        }
        return [:]
    }

    /// Reads a 4-byte little-endian UInt32 from `data` at `offset`.
    private static func le32(_ data: Data, _ offset: Int) -> Int {
        Int(UInt32(data[offset])
          | UInt32(data[offset+1]) << 8
          | UInt32(data[offset+2]) << 16
          | UInt32(data[offset+3]) << 24)
    }
}
