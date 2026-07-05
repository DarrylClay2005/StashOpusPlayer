import Foundation
import SwiftUI
import UIKit

extension AccountService {

    // MARK: - Avatar

    /// Upload a profile picture as JPEG (max 1 MB enforced server-side).
    func uploadAvatar(image: UIImage) async {
        guard isLoggedIn else { return }
        guard let jpeg = image.jpegData(compressionQuality: 0.8) else {
            appWarn("uploadAvatar: could not encode image as JPEG", category: "account")
            return
        }
        guard var req = makeBaseRequest("/user/avatar", method: "POST") else {
            appWarn("uploadAvatar: could not build request", category: "account")
            return
        }
        req.setValue("image/jpeg", forHTTPHeaderField: "Content-Type")
        req.httpBody = jpeg
        appLog("uploadAvatar: uploading \(jpeg.count / 1024)KB", category: "account")
        do {
            let (_, resp) = try await URLSession.shared.data(for: req)
            let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
            if (200..<300).contains(status) {
                appLog("uploadAvatar: success", category: "account")
            } else {
                appWarn("uploadAvatar: HTTP \(status)", category: "account")
            }
        } catch {
            appError("uploadAvatar: \(error.localizedDescription)", category: "account")
        }
        avatarImage = image
        saveAvatarLocally(image)
    }

    /// Load avatar from local cache first, then from server. Updates `avatarImage`.
    func loadAvatar(forceRefresh: Bool = false) async {
        if !forceRefresh, let cached = loadAvatarLocally() {
            avatarImage = cached
            appLog("loadAvatar: loaded from local cache", category: "account")
            return
        }
        guard isLoggedIn, let userId = currentUser?.id else { return }
        guard let req = makeBaseRequest("/user/avatar/\(userId)", method: "GET") else { return }
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
            guard (200..<300).contains(status), let img = UIImage(data: data) else {
                appWarn("loadAvatar: HTTP \(status) or invalid image data", category: "account")
                return
            }
            avatarImage = img
            saveAvatarLocally(img)
            appLog("loadAvatar: fetched from server (\(data.count / 1024)KB)", category: "account")
        } catch {
            appWarn("loadAvatar: \(error.localizedDescription)", category: "account")
        }
    }

    func makeBaseRequest(_ path: String, method: String) -> URLRequest? {
        let base = bridgeURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: base + path) else { return nil }
        var req = URLRequest(url: url)
        req.httpMethod = method
        if let t = token, !t.isEmpty {
            req.setValue("Bearer \(t)", forHTTPHeaderField: "Authorization")
        }
        return req
    }

    func saveAvatarLocally(_ image: UIImage) {
        guard let url = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("user_avatar.jpg") else { return }
        image.jpegData(compressionQuality: 0.8).flatMap { try? $0.write(to: url) }
    }

    func loadAvatarLocally() -> UIImage? {
        guard let url = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("user_avatar.jpg") else { return nil }
        return (try? Data(contentsOf: url)).flatMap { UIImage(data: $0) }
    }

    func logPlay(song: Song, listenSeconds: Int, bpm: Double? = nil) async {
        guard isLoggedIn else { return }
        struct Body: Encodable {
            let title: String
            let artist: String?
            let track_url: String?
            let local_song_id: String?
            let listen_seconds: Int
            let bpm: Double?
        }
        do {
            _ = try await makeRequest(
                "/user/history",
                method: "POST",
                body: Body(
                    title: song.title,
                    artist: song.artist.isEmpty ? nil : song.artist,
                    track_url: song.url?.absoluteString,
                    local_song_id: song.id,
                    listen_seconds: listenSeconds,
                    bpm: bpm
                )
            )
            appLog("logPlay: \"\(song.title)\" \(listenSeconds)s", category: "account")
        } catch {
            appWarn("logPlay: failed for \"\(song.title)\": \(error.localizedDescription)", category: "account")
        }
    }

    /// Pushes the current track/position to the bridge so other surfaces
    /// (e.g. the local Discord Rich Presence daemon) can mirror "now playing"
    /// for this account. Best-effort and silent on failure — this runs on
    /// every play/pause/track-change and periodically during playback, so it
    /// shouldn't spam logs or interrupt playback if the network is down.
    func pushPlaybackState(song: Song?, position: TimeInterval, duration: TimeInterval, isPlaying: Bool, bpm: Double? = nil) {
        guard isLoggedIn else { return }
        struct Body: Encodable {
            let song_id: String?
            let title: String?
            let artist: String?
            let track_url: String?
            let source: String?
            let position_seconds: Double
            let duration_seconds: Double
            let is_playing: Bool
            let bpm: Double?
        }
        let body = Body(
            song_id: song?.id,
            title: song?.title,
            artist: song?.artist.isEmpty == true ? nil : song?.artist,
            track_url: song?.url?.absoluteString,
            source: nil,
            position_seconds: position,
            duration_seconds: duration,
            is_playing: isPlaying,
            bpm: bpm
        )
        playbackStatePushTask?.cancel()
        playbackStatePushTask = Task { [weak self] in
            _ = try? await self?.makeRequest("/user/playback-state", method: "PUT", body: body)
        }
    }
}
