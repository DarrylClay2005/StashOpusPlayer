import SwiftUI
import UIKit

extension NowPlayingView {

    // MARK: - Helpers

    func labeledSlider(
        label: String,
        valueText: String,
        value: Binding<Float>,
        range: ClosedRange<Float>
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.textPrimary)
                Spacer()
                Text(valueText)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(AppTheme.textSecondary)
            }
            Slider(value: value, in: range)
                .tint(AppTheme.dynamicAccent)
        }
    }

    func audioBinding(_ keyPath: WritableKeyPath<AudioSettings, Float>) -> Binding<Float> {
        Binding {
            player.audioSettings[keyPath: keyPath]
        } set: { value in
            var settings = player.audioSettings
            settings[keyPath: keyPath] = value
            player.audioSettings = settings
        }
    }

    func formatTime(_ time: TimeInterval) -> String {
        time.formattedAsMinutesSeconds
    }

    func triggerTrackChangeAnimation() {
        // Fade/shrink the *current* artwork out first — only swap the `.id()` (which
        // tears down and recreates the artwork view) once it's invisible. Updating the
        // ID immediately used to pop the new artwork in instantly before the fade-out
        // animation had a chance to play, producing a jarring flash on every transition
        // (and especially during crossfade, where the swap happens mid-playback).
        withAnimation(.easeOut(duration: 0.15)) {
            artworkOpacity = 0
            artworkScale = 0.92
        }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 150_000_000)
            artworkAnimationID = player.currentSong?.id ?? UUID().uuidString
            withAnimation(.spring(response: 0.45, dampingFraction: 0.65)) {
                artworkOpacity = 1
                artworkScale = 1.0
            }
        }
    }

    func triggerTrackInfoAnimation() {
        // Snap the info out (invisible, shifted down), then animate back in
        trackInfoVisible = false
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 80_000_000)
            trackInfoVisible = true
        }
    }

    func loadLyrics() {
        guard let song = player.currentSong else { lyricsLines = []; return }

        // 1. User-synced lyrics saved via the in-app Lyrics Sync Editor — these
        //    represent the user's own deliberate timing work, so they take
        //    priority over a generic sidecar file or a remote guess.
        if let content = try? String(contentsOf: syncedLyricsURL(for: song), encoding: .utf8) {
            lyricsLines = LrcParser.parse(content)
            return
        }

        // 2. Sidecar .lrc file next to the audio file
        if let url = song.url {
            let lrcURL = url.deletingPathExtension().appendingPathExtension("lrc")
            if let content = try? String(contentsOf: lrcURL, encoding: .utf8) {
                lyricsLines = LrcParser.parse(content)
                return
            }
        }

        // 3. LRCLIB — free, open lyrics database with synced LRC support
        //    Falls back to LyricsOVH if LRCLIB has no synced version.
        // Clear any lyrics left over from the previous track *before* kicking
        // off the remote fetch — otherwise the previous song's lyrics stay on
        // screen (and scroll/highlight against the new song's `progress`)
        // until the network call resolves, which looks like "wrong track"
        // lyrics for the new song.
        lyricsLines = []
        let songID = song.id
        Task {
            let title  = song.title.trimmingCharacters(in: .whitespacesAndNewlines)
            let artist = song.artist.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else { return }

            // Skipping tracks fires loadLyrics() again before the previous
            // fetch resolves — an in-flight fetch for a now-stale song can
            // land after the new one and overwrite the correct lyrics with
            // the wrong song's. Bail if the user has moved on by the time
            // each remote call resolves. `currentSong` is main-actor isolated,
            // so every check has to hop over via MainActor.run.

            // LRCLIB: returns synced LRC if available
            if let lines = await fetchLRCLIB(title: title, artist: artist, duration: song.duration), !lines.isEmpty {
                await MainActor.run { if player.currentSong?.id == songID { lyricsLines = lines } }
                return
            }
            guard await MainActor.run(body: { player.currentSong?.id == songID }) else { return }

            // LyricsOVH: plain text fallback (no timestamps — shown as static block)
            if let lines = await fetchLyricsOVH(title: title, artist: artist), !lines.isEmpty {
                await MainActor.run { if player.currentSong?.id == songID { lyricsLines = lines } }
            }
        }
    }

    /// Path where `LyricsSyncEditorView` saves user-synced lyrics: `Documents/Lyrics/{songID}.lrc`.
    /// Filename sanitization must match `LyricsSyncEditorView.sanitizeFilename` exactly,
    /// or saved files silently become unreadable here.
    func syncedLyricsURL(for song: Song) -> URL {
        let illegal  = CharacterSet(charactersIn: "/:\\*?\"<>|")
        let filename = song.id.components(separatedBy: illegal).joined(separator: "_") + ".lrc"
        return FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Lyrics", isDirectory: true)
            .appendingPathComponent(filename)
    }
}
