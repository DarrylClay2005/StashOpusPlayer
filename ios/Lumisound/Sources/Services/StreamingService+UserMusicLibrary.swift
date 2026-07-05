import Foundation
import UIKit

extension StreamingService {

    // MARK: - User Music Library (personal per-user server storage)

    /// Returns the stream URL for a user music track (requires JWT token).
    func userMusicStreamURL(for track: UserMusicTrack, token: String) -> URL? {
        guard let encoded = track.serverPath.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else { return nil }
        let base = bridgeURL.trimmingCharacters(in: .init(charactersIn: "/"))
        return URL(string: "\(base)/user/music/stream?path=\(encoded)")
    }

    /// Returns the artwork URL for a user music track (requires JWT token).
    func userMusicArtworkURL(for track: UserMusicTrack) -> URL? {
        guard track.hasArtwork,
              let encoded = track.serverPath.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else { return nil }
        let base = bridgeURL.trimmingCharacters(in: .init(charactersIn: "/"))
        return URL(string: "\(base)/user/music/artwork?path=\(encoded)")
    }

    /// Wraps a `UserMusicTrack` in a `Song` for playback.
    func toSong(userMusicTrack: UserMusicTrack, token: String) -> Song {
        let streamURL = userMusicStreamURL(for: userMusicTrack, token: token)
        let artworkKey = userMusicArtworkURL(for: userMusicTrack)?.absoluteString
        return Song(
            id: userMusicTrack.id,
            title: userMusicTrack.title,
            artist: userMusicTrack.artist,
            album: userMusicTrack.album,
            duration: userMusicTrack.duration,
            url: streamURL,
            persistentID: nil,
            artworkCacheKey: artworkKey,
            trackNumber: Int(userMusicTrack.trackNumber) ?? 0,
            year: "",
            genre: userMusicTrack.genre,
            bitrate: 0,
            sampleRate: 0,
            httpHeaders: ["Authorization": "Bearer \(token)"]
        )
    }

    /// Fetches the user's personal music library from the server.
    func fetchUserMusic(token: String, search: String = "") async {
        appLog("fetchUserMusic: search=\"\(search)\"", category: "network")
        isLoadingUserMusic = true
        errorMessage = nil
        defer { isLoadingUserMusic = false }

        var components = URLComponents()
        components.path = "/user/music"
        components.queryItems = [
            // No 500-item cap on the user's cloud library (server allows up to 100k).
            URLQueryItem(name: "limit", value: "100000"),
        ]
        if !search.isEmpty {
            components.queryItems?.append(URLQueryItem(name: "search", value: search))
        }

        guard var request = makeRequest(components.string ?? "/user/music") else {
            errorMessage = "Invalid bridge URL."
            return
        }
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        // The first request after a library change has to ffprobe every
        // uncached file server-side before it can respond — with a large
        // personal library this routinely took longer than the old 20s
        // timeout, which made "My Library" appear to hang/fail forever even
        // though the server was still working (and would have served a fast,
        // cached response on the next try). 90s gives that cold pass room to
        // finish; subsequent calls hit the server's ffprobe cache and return
        // quickly regardless.
        request.timeoutInterval = 90

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let httpResponse = response as? HTTPURLResponse, !(200..<300).contains(httpResponse.statusCode) {
                appWarn("fetchUserMusic: HTTP \(httpResponse.statusCode)", category: "network")
                if httpResponse.statusCode == 401 {
                    errorMessage = "Your session has expired. Please log in again."
                } else {
                    errorMessage = "Streaming service error (HTTP \(httpResponse.statusCode)). Please try again later."
                }
                return
            }

            struct Response: Decodable {
                let tracks: [UserMusicTrack]
                let total: Int
                let configured: Bool
            }
            let decoded = try JSONDecoder().decode(Response.self, from: data)
            if !decoded.configured {
                errorMessage = "User music storage is not configured on the server."
                userMusicTracks = []
            } else {
                userMusicTracks = decoded.tracks
                appLog("fetchUserMusic: \(decoded.tracks.count) tracks", category: "network")
            }
        } catch {
            appError("fetchUserMusic: \(error.localizedDescription)", category: "network")
            errorMessage = "Failed to load your library: \(error.localizedDescription)"
        }
    }

    /// Fetches the tracks this account has downloaded before (server-side
    /// history), optionally filtered by `search`. Used by "My Library" search
    /// to surface tracks the user has ever had — even ones no longer present
    /// on this device — and by the "previously downloaded" restore list.
    func fetchDownloadHistory(token: String, search: String = "") async {
        appLog("fetchDownloadHistory: search=\"\(search)\"", category: "network")
        isLoadingDownloadHistory = true
        defer { isLoadingDownloadHistory = false }

        var components = URLComponents()
        components.path = "/user/download-history"
        components.queryItems = [URLQueryItem(name: "limit", value: "200")]
        if !search.isEmpty {
            components.queryItems?.append(URLQueryItem(name: "search", value: search))
        }

        guard var request = makeRequest(components.string ?? "/user/download-history") else {
            return
        }
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let httpResponse = response as? HTTPURLResponse, !(200..<300).contains(httpResponse.statusCode) {
                appWarn("fetchDownloadHistory: HTTP \(httpResponse.statusCode)", category: "network")
                return
            }
            struct Response: Decodable {
                let tracks: [DownloadHistoryTrack]
                let total: Int
            }
            let decoded = try JSONDecoder().decode(Response.self, from: data)
            downloadHistory = decoded.tracks
            appLog("fetchDownloadHistory: \(decoded.tracks.count) tracks", category: "network")
        } catch {
            appError("fetchDownloadHistory: \(error.localizedDescription)", category: "network")
        }
    }

    /// Uploads a local audio file to the user's personal music library on the server.
    func uploadToUserLibrary(fileURL: URL, token: String, folder: String = "") async throws {
        appLog("uploadToUserLibrary: \(fileURL.lastPathComponent)", category: "network")
        isUploadingUserMusic = true
        uploadProgress = 0
        defer { isUploadingUserMusic = false; uploadProgress = 0 }

        let filename = fileURL.lastPathComponent
        var components = URLComponents()
        components.path = "/user/music/upload"
        components.queryItems = [
            URLQueryItem(name: "filename", value: filename),
        ]
        if !folder.isEmpty {
            components.queryItems?.append(URLQueryItem(name: "folder", value: folder))
        }

        guard var request = makeRequest(components.string ?? "/user/music/upload") else {
            throw StreamingError.invalidURL
        }
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 300   // 5 min for large files

        // Use URLSession.upload(for:fromFile:) instead of loading the whole file into memory.
        // This streams the file directly from disk, critical for large audio files.
        let (_, response) = try await URLSession.shared.upload(for: request, fromFile: fileURL)
        if let http = response as? HTTPURLResponse {
            switch http.statusCode {
            case 200..<300: break
            case 413: throw StreamingError.httpError(413)
            default: throw StreamingError.httpError(http.statusCode)
            }
        }
        appLog("uploadToUserLibrary: uploaded \(filename)", category: "network")
    }

    /// Deletes a file from the user's personal music library on the server.
    func deleteUserMusic(path: String, token: String) async throws {
        let encoded = path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? path
        guard var request = makeRequest("/user/music/\(encoded)") else {
            throw StreamingError.invalidURL
        }
        request.httpMethod = "DELETE"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 20

        let (_, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw StreamingError.httpError(http.statusCode)
        }
        appLog("deleteUserMusic: deleted \(path)", category: "network")
    }
}
