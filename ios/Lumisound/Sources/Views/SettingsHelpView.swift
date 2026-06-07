import SwiftUI

// MARK: - SettingsHelpView

struct SettingsHelpView: View {

    var body: some View {
        List {
            playbackSection
            audioEffectsSection
            librarySection
            backgroundGallerySection
            streamingSection
            accountSection
            nowPlayingSection
            widgetsSection
        }
        .scrollContentBackground(.hidden)
        .background(GalleryBackgroundView().ignoresSafeArea())
        .navigationTitle("Help & Feature Guide")
        .navigationBarTitleDisplayMode(.large)
        .toolbarBackground(.hidden, for: .navigationBar)
    }

    // MARK: — Playback Section

    private var playbackSection: some View {
        Section {
            helpRow(
                icon: "waveform.path.ecg",
                title: "Crossfade",
                body: "Crossfade smoothly blends the end of one track into the beginning of the next so there is no sudden silence between songs. The duration slider controls how many seconds the overlap lasts — shorter values (1–3 s) give a subtle fade, longer values (6–10 s) produce a DJ-style blend. Crossfade works best with music at similar tempos."
            )
            helpRow(
                icon: "infinity",
                title: "Gapless Playback",
                body: "Gapless playback removes all silence between tracks so they play back-to-back without any pause. This is different from crossfade — the songs do not overlap; they simply butt up against each other seamlessly. It is ideal for live albums, DJ sets, and concept records designed to flow as one continuous piece."
            )
            helpRow(
                icon: "repeat",
                title: "A–B Repeat",
                body: "A–B Repeat lets you loop a precise segment of a track. Tap A to mark the start point and B to mark the end point while a song is playing; the app then loops only that region indefinitely. Tap Clear to remove the markers and resume normal playback. Useful for learning music, transcribing passages, or drilling a specific section."
            )
            helpRow(
                icon: "moon.zzz",
                title: "Sleep Timer",
                body: "The Sleep Timer pauses playback after a set amount of time — useful for falling asleep to music without leaving audio running all night. Choose a preset duration (5 minutes to 2 hours) and tap Start. The remaining time appears as a pill in Now Playing. Tapping the pill opens the timer sheet where you can cancel early."
            )
            helpRow(
                icon: "sparkles",
                title: "Auto-Radio",
                body: "Auto-Radio automatically appends new songs to the queue when it is about to run out. When the last track finishes, Lumisound searches YouTube via the bridge server for songs similar to the one you were just listening to and queues up the top results. Toggle it on in the Now Playing screen. A bridge server must be configured for this feature to work."
            )
            helpRow(
                icon: "speaker.wave.3",
                title: "ReplayGain",
                body: "ReplayGain normalises the perceived loudness across your library so you do not have to keep adjusting the volume when switching between tracks recorded at different levels. The app reads the REPLAYGAIN_TRACK_GAIN and REPLAYGAIN_ALBUM_GAIN metadata tags embedded in your audio files. If a file has no gain tag the track is played at its original volume."
            )
        } header: {
            sectionHeader("Playback")
        }
        .listRowBackground(AppTheme.surface)
    }

    // MARK: — Audio Effects Section

    private var audioEffectsSection: some View {
        Section {
            helpRow(
                icon: "slider.vertical.3",
                title: "EQ Presets",
                body: "The 10-band equalizer ships with several presets tuned for different listening styles. Flat leaves all bands at 0 dB (no colouration). Bass Boost emphasises the low end. Treble Boost brightens the high end. Vocal/Podcast scoops the sub-bass and boosts the mid-range where speech sits. Custom lets you drag each band freely and saves your settings automatically."
            )
            helpRow(
                icon: "waveform.path",
                title: "Bass Boost",
                body: "Bass Boost is a quick single-toggle alternative to the full EQ that amplifies the 32 Hz and 64 Hz frequency bands. The Boost Gain slider lets you dial in how much extra punch you want, from a gentle 2 dB lift to a heavy 15 dB boost. The effect is separate from the EQ bands so you can combine both if needed."
            )
            helpRow(
                icon: "circle.grid.3x3",
                title: "8D Audio",
                body: "8D Audio applies a rotating panning effect that makes the sound appear to move around your head when listening on headphones. The audio sweeps left and right in a slow cycle, giving the impression of three-dimensional space. It is an artistic effect and works best with headphones; on speakers the effect is minimal."
            )
            helpRow(
                icon: "waveform",
                title: "Tremolo",
                body: "Tremolo modulates the volume of the audio at a regular rate, creating a rhythmic wavering effect familiar from vintage guitar amplifiers and 1960s recordings. You can adjust the rate (how fast the volume pulses) and depth (how extreme the dip is). Subtle settings add warmth; high-depth settings at fast rates produce a choppy, effect-heavy sound."
            )
            helpRow(
                icon: "tuningfork",
                title: "Vibrato",
                body: "Vibrato modulates the pitch of the audio at a regular rate, producing the characteristic wobble heard in classical violin technique and vintage synthesizers. Rate controls the speed of the pitch oscillation and depth controls how wide the pitch swings. Like tremolo it is an artistic effect that can range from barely perceptible to exaggerated."
            )
            helpRow(
                icon: "mic.slash",
                title: "Karaoke Mode",
                body: "Karaoke Mode attempts to remove or reduce vocals from a stereo recording by phase-cancelling the centre channel where lead vocals are typically panned. The effect is not perfect and its quality depends heavily on the mix of the original recording. Songs where the vocal is hard-panned or heavily processed will not respond as well as straightforward pop mixes."
            )
            helpRow(
                icon: "hare",
                title: "Pitch & Speed",
                body: "The Speed slider changes how fast the audio plays, from 0.5× (half-speed) to 2.0× (double-speed), without affecting pitch. The Pitch slider shifts the pitch up or down by up to 12 semitones independently of speed. Tap the pencil icon next to either value to type in an exact number. These controls are also accessible in the Now Playing screen under Playback Controls."
            )
        } header: {
            sectionHeader("Audio Effects")
        }
        .listRowBackground(AppTheme.surface)
    }

    // MARK: — Library Section

    private var librarySection: some View {
        Section {
            helpRow(
                icon: "music.note.house",
                title: "Scanning iPhone Library",
                body: "Lumisound can read your Apple Music / iTunes library directly from the iPhone without any file transfer. Go to Settings → Library and tap Grant Access, then approve the media library permission. After permission is granted, tap Scan Library to import all your songs, albums, artists, and playlists. The scan runs in the background and updates the counts automatically."
            )
            helpRow(
                icon: "folder.badge.plus",
                title: "Importing Files",
                body: "You can import audio files (MP3, AAC, FLAC, ALAC, OGG, OPUS, WAV, and more) from the Files app using the Add Music button in the Library tab. Files are copied into Lumisound's private Documents folder so they remain available even if the original location changes. Drag and drop from other apps on iPad is also supported."
            )
            helpRow(
                icon: "folder.badge.gearshape",
                title: "Watched Folders",
                body: "Watched Folders let you point Lumisound at a folder inside the Files app (for example an iCloud Drive folder or a USB drive via the Files app) and have it automatically include any audio files found there in your library. The folder is rescanned every time the app launches. Tap the folder icon on the Library screen to add or remove watched folders."
            )
            helpRow(
                icon: "square.grid.2x2",
                title: "Column & Grid Layouts",
                body: "The Songs tab offers a list view (1 column) and grid views (2 or 3 columns). Tap the layout icons in the top-right corner to switch between them. The Albums tab similarly supports 1, 2, or 3 column grids. Your layout preference is saved per-section and restored the next time you open the app."
            )
            helpRow(
                icon: "arrow.up.arrow.down",
                title: "Sort Options",
                body: "Songs in the library are sorted alphabetically by title by default. Use the search bar to filter the visible list in real time — results update after a short debounce delay so the app does not re-render on every keystroke. Artists and albums are sorted alphabetically. Playlists appear in the order you created them."
            )
        } header: {
            sectionHeader("Library")
        }
        .listRowBackground(AppTheme.surface)
    }

    // MARK: — Background Gallery Section

    private var backgroundGallerySection: some View {
        Section {
            helpRow(
                icon: "photo.on.rectangle",
                title: "How It Works",
                body: "The Gallery Background renders a full-screen image behind all app screens, giving Lumisound its distinctive look. You can add any photos from your Camera Roll or Files app in Settings → Appearance → Gallery Background. When multiple images are added the gallery shuffles through them at a configurable interval. If no images are added the app falls back to its default colour gradient."
            )
            helpRow(
                icon: "sparkle",
                title: "Animation Types",
                body: "The gallery supports three animation styles: Ken Burns slowly zooms and pans the image to create the documentary film effect; Fade cross-fades between images without motion; Static displays each image without any transition. Ken Burns is the default and works well with landscape photography. Choose Fade or Static if you prefer a calmer, less distracting background."
            )
            helpRow(
                icon: "slider.horizontal.3",
                title: "Blur & Opacity Controls",
                body: "A blur slider softens the background image so it does not compete with text and controls in the foreground. A separate opacity slider lets you fade the image towards the app's base colour. Combining a moderate blur (around 20–40) with a slight opacity reduction (0.7–0.9) gives a frosted-glass effect that looks good across many photos."
            )
            helpRow(
                icon: "timer",
                title: "Shuffle Interval",
                body: "When multiple gallery images are loaded, the interval slider controls how long each image is displayed before transitioning to the next one. The interval ranges from 10 seconds up to several minutes. A shorter interval creates a livelier animated backdrop; a longer interval keeps the background stable so it is less distracting during focused listening sessions."
            )
        } header: {
            sectionHeader("Background Gallery")
        }
        .listRowBackground(AppTheme.surface)
    }

    // MARK: — Streaming Section

    private var streamingSection: some View {
        Section {
            helpRow(
                icon: "server.rack",
                title: "Bridge Server",
                body: "The bridge server is a small companion service you run on your home computer or server. It acts as a proxy between Lumisound and streaming platforms like YouTube and SoundCloud, handling the audio extraction so iOS does not have to. Enter the server's local IP address and port (e.g. http://192.168.1.10:7333) in Settings → Streaming. The server and your iPhone must be on the same network, or the server must be accessible via a VPN or public URL."
            )
            helpRow(
                icon: "link",
                title: "Setting It Up",
                body: "Download the bridge server from the project's GitHub releases page and run it on your Mac, Windows PC, or Linux machine. Once it is running, open Lumisound, enter the server URL in Settings → Streaming, and tap Test Connection. A green checkmark confirms the app can reach it. You can optionally set an API key in both the server config and in Lumisound for authentication. No setup is required to use the local library or your iPhone's Apple Music library."
            )
            helpRow(
                icon: "magnifyingglass",
                title: "YouTube & SoundCloud Search",
                body: "Once the bridge server is configured, the Search tab lets you search YouTube and SoundCloud by title, artist, or paste a full playlist URL. Search results show thumbnail, title, artist, and duration. Tap the play button to stream a track immediately or the download button to save it to your local library. Pasting a YouTube playlist URL fetches the full track list so you can download the entire playlist at once."
            )
            helpRow(
                icon: "waveform",
                title: "Audio Format Preference",
                body: "The Audio Format picker in Settings → Streaming tells the bridge server which container to request from the platform: Opus (best quality per kilobyte, default), MP3 (maximum compatibility), AAC, or Best Available (lets the server choose). Opus is recommended over a home network. Use MP3 if your server's version of yt-dlp has issues with Opus extraction."
            )
        } header: {
            sectionHeader("Streaming")
        }
        .listRowBackground(AppTheme.surface)
    }

    // MARK: — Account Section

    private var accountSection: some View {
        Section {
            helpRow(
                icon: "icloud",
                title: "What Gets Synced",
                body: "Your Lumisound account syncs your favourites list, playlists (names, track order, and membership), and audio settings (EQ, speed, pitch, crossfade, etc.) to the server. This lets you restore everything after reinstalling the app or switching to a new device. The actual audio files are not uploaded — only the metadata and preferences."
            )
            helpRow(
                icon: "arrow.up.to.cloud",
                title: "Push Sync",
                body: "A push sync writes your current favourites, playlists, and audio settings up to the server. Pushes happen automatically in the background a few seconds after any change so you normally do not need to trigger them manually. The Account screen shows the last sync time and provides a manual Push button if you want to force an immediate upload."
            )
            helpRow(
                icon: "arrow.down.from.cloud",
                title: "Pull Sync",
                body: "A pull sync downloads the latest saved state from the server and applies it locally. Pull happens automatically when you log in and on every app launch while you are signed in. You can also trigger a manual pull from the Account screen. If your local favourites differ from the server, the server version wins — so make sure to push before uninstalling if you want to preserve recent changes."
            )
            helpRow(
                icon: "arrow.counterclockwise",
                title: "After Reinstall",
                body: "After reinstalling Lumisound, sign in with the same account and the app will automatically pull your favourites, playlists, and settings from the server. Your local audio files will not be restored automatically — you will need to re-scan Apple Music or re-import transferred files. Any streaming downloads that were saved to the app's Documents folder will also be gone and need to be re-downloaded."
            )
        } header: {
            sectionHeader("Account")
        }
        .listRowBackground(AppTheme.surface)
    }

    // MARK: — Now Playing Section

    private var nowPlayingSection: some View {
        Section {
            helpRow(
                icon: "circle.fill",
                title: "Vinyl Disc vs Album Art",
                body: "The artwork style picker at the top of the Now Playing screen lets you switch between two visual modes. Vinyl Disc renders a spinning record with concentric groove rings and the album art printed in the centre; it rotates while the song plays and stops when paused. Album Art mode shows the full square artwork in a plain card with a drop shadow. Your choice is saved and persists between sessions."
            )
            helpRow(
                icon: "waveform.badge.clock",
                title: "Timeline & Seeking",
                body: "The timeline slider shows your current position in the track. Drag the thumb to scrub to any point; the elapsed and remaining time labels update in real time while you drag. Release to confirm the seek. The slider is disabled while the duration is unknown (for example at the very start of a stream)."
            )
            helpRow(
                icon: "heart",
                title: "Favourite Button",
                body: "The heart icon to the right of the track title toggles the current song as a favourite. Favourited songs appear in the Favorites tab in the Library and are included in synced account data. The heart fills with the accent colour when active and springs with a subtle animation on tap."
            )
            helpRow(
                icon: "list.number",
                title: "Up Next Queue",
                body: "The Up Next panel shows the next 10 songs in the queue as a horizontal scroll of artwork thumbnails. The first thumbnail has an accent-coloured border to indicate it plays next. Tap any thumbnail to jump straight to that song. The badge on the panel header shows total queue length and a shuffle icon appears when shuffle is enabled."
            )
        } header: {
            sectionHeader("Now Playing")
        }
        .listRowBackground(AppTheme.surface)
    }

    // MARK: — Widgets Section

    private var widgetsSection: some View {
        Section {
            helpRow(
                icon: "apps.iphone",
                title: "Adding the Widget",
                body: "Long-press the Home Screen or Lock Screen until the icons jiggle, then tap the + button in the top-left corner. Search for \"Lumisound\" in the widget gallery. Choose between the small (1×1) or medium (2×1) size and tap Add Widget. The widget is live and updates automatically whenever the currently playing track changes."
            )
            helpRow(
                icon: "music.note",
                title: "What It Shows",
                body: "The Lumisound widget displays the album artwork, song title, and artist name for the currently playing track. It refreshes through the Darwin notification bridge so changes appear within a second or two of the track changing. If nothing is playing the widget shows the Lumisound logo and a prompt to open the app."
            )
            helpRow(
                icon: "lock.iphone",
                title: "Lock Screen vs Home Screen",
                body: "The Lock Screen widget is a smaller inline or accessory rectangular format that shows the song title and artist in a compact single line. The Home Screen widget is the standard rounded-corner square that shows artwork alongside the track info. Both support Dark Mode and adapt to the current accent colour set in Appearance settings."
            )
        } header: {
            sectionHeader("Widgets")
        }
        .listRowBackground(AppTheme.surface)
    }

    // MARK: — Helpers

    private func sectionHeader(_ text: String) -> some View {
        Text(text.uppercased())
            .font(AppTheme.bodyFont(size: 11))
            .foregroundStyle(AppTheme.textSecondary)
            .kerning(0.8)
    }

    private func helpRow(icon: String, title: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(AppTheme.dynamicAccent)
                    .frame(width: 26, alignment: .center)
                Text(title)
                    .font(AppTheme.headlineFont(size: 15))
                    .foregroundStyle(AppTheme.textPrimary)
            }
            Text(body)
                .font(AppTheme.bodyFont(size: 13))
                .foregroundStyle(AppTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.leading, 36)
        }
        .padding(.vertical, 6)
    }
}
