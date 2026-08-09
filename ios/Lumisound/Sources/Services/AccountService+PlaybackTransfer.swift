import Foundation

extension AccountService {

    // MARK: - Cross-Device Playback Handoff

    /// Fetches this account's registered devices (push-token rows with
    /// display metadata), most recently seen first. Powers the transfer
    /// target picker.
    func fetchDevices() async -> [RegisteredDevice] {
        guard isLoggedIn else { return [] }
        do {
            let data = try await makeRequest("/user/devices")
            return try JSONDecoder().decode([RegisteredDevice].self, from: data)
        } catch {
            errorMessage = (error as? AccountError)?.message ?? error.localizedDescription
            return []
        }
    }

    /// Sends `song`'s current playback state to `device` and asks it to
    /// start playing. Mirrors the same `sourceTrackID` "prefix:bareID"
    /// splitting `pushPlaybackState` (AccountService+Avatar.swift) already
    /// uses for the Discord Rich Presence button URL — same underlying
    /// field, same convention, just handed to a different endpoint.
    @discardableResult
    func transferPlayback(song: Song, position: TimeInterval, duration: TimeInterval, isPlaying: Bool, to device: RegisteredDevice, bpm: Double? = nil) async -> Bool {
        guard isLoggedIn else { return false }
        struct Body: Encodable {
            let target_device_token: String
            let song_id: String?
            let title: String
            let artist: String?
            let track_url: String?
            let source: String?
            let source_id: String?
            let thumbnail_url: String?
            let position_seconds: Double
            let duration_seconds: Double
            let is_playing: Bool
            let bpm: Double?
        }

        var sourcePrefix: String?
        var bareSourceID: String?
        if let sourceTrackID = song.sourceTrackID, let colonIndex = sourceTrackID.firstIndex(of: ":") {
            sourcePrefix = String(sourceTrackID[sourceTrackID.startIndex..<colonIndex])
            bareSourceID = String(sourceTrackID[sourceTrackID.index(after: colonIndex)...])
        }
        let webURL: String? = {
            guard let sourcePrefix, let bareSourceID, !bareSourceID.isEmpty else { return nil }
            switch sourcePrefix {
            case "youtube": return "https://youtube.com/watch?v=\(bareSourceID)"
            default: return nil
            }
        }()

        let body = Body(
            target_device_token: device.deviceToken,
            song_id: song.id,
            title: song.title,
            artist: song.artist.isEmpty ? nil : song.artist,
            track_url: webURL,
            source: sourcePrefix,
            source_id: bareSourceID,
            thumbnail_url: nil,
            position_seconds: position,
            duration_seconds: duration,
            is_playing: isPlaying,
            bpm: bpm
        )
        do {
            _ = try await makeRequest("/user/playback/transfer", method: "POST", body: body)
            return true
        } catch let err as AccountError {
            errorMessage = err.message
            return false
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }
}
