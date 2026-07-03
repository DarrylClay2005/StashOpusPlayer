import SwiftUI

// MARK: - HelpTopic

/// A single help entry — one row in a `SettingsHelpDetailView`.
private struct HelpTopic: Identifiable {
    let id = UUID()
    let icon: String
    let title: String
    let body: String
}

// MARK: - HelpCategory

/// A top-level entry in the Help & Feature Guide index. Each category opens
/// its own page of `HelpTopic`s, rather than the guide being one long scroll
/// of every topic at once.
private struct HelpCategory: Identifiable {
    let id = UUID()
    let icon: String
    let title: String
    let topics: [HelpTopic]
}

// MARK: - SettingsHelpView

struct SettingsHelpView: View {

    var body: some View {
        List {
            Section {
                ForEach(Self.categories) { category in
                    NavigationLink(destination: SettingsHelpDetailView(category: category)) {
                        Label(category.title, systemImage: category.icon)
                            .foregroundStyle(AppTheme.textPrimary)
                    }
                }
            } header: {
                sectionHeader("Topics")
            } footer: {
                Text("Pick a category for details on what each feature does and how to use it.")
                    .font(AppTheme.bodyFont(size: 12))
                    .foregroundStyle(AppTheme.textSecondary)
            }
            .listRowBackground(AppTheme.surface)
        }
        .scrollContentBackground(.hidden)
        .background(GalleryBackgroundView().ignoresSafeArea())
        .navigationTitle("Help & Feature Guide")
        .navigationBarTitleDisplayMode(.large)
        .toolbarBackground(.hidden, for: .navigationBar)
    }

    private func sectionHeader(_ text: String) -> some View {
        Text(text.uppercased())
            .font(AppTheme.bodyFont(size: 11))
            .foregroundStyle(AppTheme.textSecondary)
            .kerning(0.8)
    }

    // MARK: — Category Data

    private static let categories: [HelpCategory] = [
        HelpCategory(icon: "play.circle", title: "Playback", topics: [
            HelpTopic(
                icon: "waveform.path.ecg",
                title: "Crossfade",
                body: "Crossfade smoothly blends the end of one track into the beginning of the next so there is no sudden silence between songs. The duration slider controls how many seconds the overlap lasts — shorter values (1–3 s) give a subtle fade, longer values (6–10 s) produce a DJ-style blend. Crossfade works best with music at similar tempos."
            ),
            HelpTopic(
                icon: "infinity",
                title: "Gapless Playback",
                body: "Gapless playback removes all silence between tracks so they play back-to-back without any pause. This is different from crossfade — the songs do not overlap; they simply butt up against each other seamlessly. It is ideal for live albums, DJ sets, and concept records designed to flow as one continuous piece."
            ),
            HelpTopic(
                icon: "repeat",
                title: "A–B Repeat",
                body: "A–B Repeat lets you loop a precise segment of a track. Tap A to mark the start point and B to mark the end point while a song is playing; the app then loops only that region indefinitely. Tap Clear to remove the markers and resume normal playback. Useful for learning music, transcribing passages, or drilling a specific section."
            ),
            HelpTopic(
                icon: "moon.zzz",
                title: "Sleep Timer",
                body: "The Sleep Timer pauses playback after a set amount of time — useful for falling asleep to music without leaving audio running all night. Choose a preset duration (5 minutes to 2 hours) and tap Start. The remaining time appears as a pill in Now Playing. Tapping the pill opens the timer sheet where you can cancel early."
            ),
            HelpTopic(
                icon: "sparkles",
                title: "Auto-Radio",
                body: "Auto-Radio automatically appends new songs to the queue when it is about to run out. When the last track finishes, Lumisound searches YouTube for songs similar to the one you were just listening to and queues up the top results. Toggle it on in the Now Playing screen. Requires an internet connection."
            ),
            HelpTopic(
                icon: "speaker.wave.3",
                title: "ReplayGain",
                body: "ReplayGain normalises the perceived loudness across your library so you do not have to keep adjusting the volume when switching between tracks recorded at different levels. The app reads the REPLAYGAIN_TRACK_GAIN and REPLAYGAIN_ALBUM_GAIN metadata tags embedded in your audio files. If a file has no gain tag the track is played at its original volume."
            ),
            HelpTopic(
                icon: "speaker.wave.3.fill",
                title: "Volume Boost",
                body: "The volume slider in Now Playing can go above 100%, up to 200%, for tracks recorded at a low level. A limiter automatically smooths out loud peaks so the boosted output doesn't crackle or distort — you'll see a \"Boost\" label appear once you go past 100%."
            ),
            HelpTopic(
                icon: "pin",
                title: "Per-Track Sound Settings",
                body: "Adjust the EQ, effects, volume, or any other sound setting for the current track, then tap Save in the \"Custom Sound for This Track\" panel in Now Playing to pin those settings to that song specifically. They'll be recalled automatically every time the track plays, without affecting your default settings for everything else. Tap Remove to go back to your defaults for that track."
            ),
        ]),
        HelpCategory(icon: "slider.vertical.3", title: "Audio Effects", topics: [
            HelpTopic(
                icon: "slider.vertical.3",
                title: "EQ Presets",
                body: "The 10-band equalizer ships with several presets tuned for different listening styles. Flat leaves all bands at 0 dB (no colouration). Bass Boost emphasises the low end. Treble Boost brightens the high end. Vocal/Podcast scoops the sub-bass and boosts the mid-range where speech sits. Custom lets you drag each band freely and saves your settings automatically."
            ),
            HelpTopic(
                icon: "waveform.path",
                title: "Bass Boost",
                body: "Bass Boost is a quick single-toggle alternative to the full EQ that amplifies the 32 Hz and 64 Hz frequency bands. The Boost Gain slider lets you dial in how much extra punch you want, from a gentle 2 dB lift to a heavy 15 dB boost. The effect is separate from the EQ bands so you can combine both if needed."
            ),
            HelpTopic(
                icon: "circle.grid.3x3",
                title: "8D Audio",
                body: "8D Audio applies a rotating panning effect that makes the sound appear to move around your head when listening on headphones. The audio sweeps left and right in a slow cycle, giving the impression of three-dimensional space. It is an artistic effect and works best with headphones; on speakers the effect is minimal."
            ),
            HelpTopic(
                icon: "waveform",
                title: "Tremolo",
                body: "Tremolo modulates the volume of the audio at a regular rate, creating a rhythmic wavering effect familiar from vintage guitar amplifiers and 1960s recordings. You can adjust the rate (how fast the volume pulses) and depth (how extreme the dip is). Subtle settings add warmth; high-depth settings at fast rates produce a choppy, effect-heavy sound."
            ),
            HelpTopic(
                icon: "tuningfork",
                title: "Vibrato",
                body: "Vibrato modulates the pitch of the audio at a regular rate, producing the characteristic wobble heard in classical violin technique and vintage synthesizers. Rate controls the speed of the pitch oscillation and depth controls how wide the pitch swings. Like tremolo it is an artistic effect that can range from barely perceptible to exaggerated."
            ),
            HelpTopic(
                icon: "mic.slash",
                title: "Karaoke Mode",
                body: "Karaoke Mode attempts to remove or reduce vocals from a stereo recording by phase-cancelling the centre channel where lead vocals are typically panned. The effect is not perfect and its quality depends heavily on the mix of the original recording. Songs where the vocal is hard-panned or heavily processed will not respond as well as straightforward pop mixes."
            ),
            HelpTopic(
                icon: "hare",
                title: "Pitch & Speed",
                body: "The Speed slider changes how fast the audio plays, from 0.5× (half-speed) to 2.0× (double-speed), without affecting pitch. The Pitch slider shifts the pitch up or down by up to 12 semitones independently of speed. Tap the pencil icon next to either value to type in an exact number. These controls are also accessible in the Now Playing screen under Playback Controls."
            ),
        ]),
        HelpCategory(icon: "music.note.list", title: "Library", topics: [
            HelpTopic(
                icon: "music.note.house",
                title: "Scanning iPhone Library",
                body: "Lumisound can read your Apple Music / iTunes library directly from the iPhone without any file transfer. Go to Settings → Library and tap Grant Access, then approve the media library permission. After permission is granted, tap Scan Library to import all your songs, albums, artists, and playlists. The scan runs in the background and updates the counts automatically."
            ),
            HelpTopic(
                icon: "folder.badge.plus",
                title: "Importing Files",
                body: "You can import audio files (MP3, AAC, FLAC, ALAC, OGG, OPUS, WAV, and more) from the Files app using the Add Music button in the Library tab. Files are copied into Lumisound's private Documents folder so they remain available even if the original location changes. Drag and drop from other apps on iPad is also supported."
            ),
            HelpTopic(
                icon: "folder.badge.gearshape",
                title: "Watched Folders",
                body: "Watched Folders let you point Lumisound at a folder inside the Files app (for example an iCloud Drive folder or a USB drive via the Files app) and have it automatically include any audio files found there in your library. The folder is rescanned every time the app launches. Tap the folder icon on the Library screen to add or remove watched folders."
            ),
            HelpTopic(
                icon: "square.grid.2x2",
                title: "Column & Grid Layouts",
                body: "The Songs tab offers a list view (1 column) and grid views (2 or 3 columns). Tap the layout icons in the top-right corner to switch between them. The Albums tab similarly supports 1, 2, or 3 column grids. Your layout preference is saved per-section and restored the next time you open the app."
            ),
            HelpTopic(
                icon: "arrow.up.arrow.down",
                title: "Sort Options",
                body: "Songs in the library are sorted alphabetically by title by default. Use the search bar to filter the visible list in real time — results update after a short debounce delay so the app does not re-render on every keystroke. Artists and albums are sorted alphabetically. Playlists appear in the order you created them."
            ),
            HelpTopic(
                icon: "arrow.clockwise",
                title: "Refresh",
                body: "The refresh button in the top-right of the Library tab re-scans your Documents folder, watched folders, and (if you've granted access) your Apple Music library for new or changed files. If you're signed in, it also pulls your latest favourites, playlists, and settings from the server — useful after making changes on another device."
            ),
            HelpTopic(
                icon: "wand.and.stars",
                title: "Automatic Metadata Lookup",
                body: "Whenever new tracks are scanned in, Lumisound reads the title, artist, album, genre, and year embedded in the file, and fills in anything still missing using online lookups (iTunes, MusicBrainz, and Deezer). Lumisound also periodically re-checks any imported track that's still missing artist, album, genre, or year — for example after deleting and reinstalling the app and copying your music back from a backup folder — so those tracks fill in automatically the next time the app is open, without needing a manual rescan."
            ),
        ]),
        HelpCategory(icon: "photo.on.rectangle", title: "Background Gallery", topics: [
            HelpTopic(
                icon: "photo.on.rectangle",
                title: "How It Works",
                body: "The Gallery Background renders a full-screen image behind all app screens, giving Lumisound its distinctive look. You can add any photos from your Camera Roll or Files app in Settings → Appearance → Gallery Background. When multiple images are added the gallery shuffles through them at a configurable interval. If no images are added the app falls back to its default colour gradient."
            ),
            HelpTopic(
                icon: "sparkle",
                title: "Animation Types",
                body: "Pick how the gallery transitions between images in Settings → Appearance → Gallery Background: Fade cross-fades smoothly; Slide Left and Slide Up pan the next image in from the side or bottom; Zoom In and Zoom Out scale the incoming image while it fades in; Flip rotates between images with a 3D-style effect; Blur In brings the next image into focus; and Cut switches instantly with no animation. Choose a calmer style like Fade or Cut if you prefer a less distracting background."
            ),
            HelpTopic(
                icon: "slider.horizontal.3",
                title: "Blur & Opacity Controls",
                body: "A blur slider softens the background image so it does not compete with text and controls in the foreground. A separate opacity slider lets you fade the image towards the app's base colour. Combining a moderate blur (around 20–40) with a slight opacity reduction (around 0.3–0.5) gives a frosted-glass effect that looks good across many photos."
            ),
            HelpTopic(
                icon: "timer",
                title: "Shuffle Interval",
                body: "When multiple gallery images are loaded, the interval picker controls how long each image is displayed before transitioning to the next one, from every 5 seconds up to every 5 minutes. A shorter interval creates a livelier animated backdrop; a longer interval keeps the background stable so it is less distracting during focused listening sessions."
            ),
            HelpTopic(
                icon: "icloud",
                title: "Synced Per Account",
                body: "Whether the gallery is on or off, the animation style, blur, opacity, and shuffle interval are all saved to your account along with your favourites and playlists. Signing in on another device, or signing into a different account on this device, applies your saved background settings immediately. Your gallery images themselves are also backed up automatically while signed in (see Account → After Reinstall)."
            ),
        ]),
        HelpCategory(icon: "magnifyingglass", title: "Streaming", topics: [
            HelpTopic(
                icon: "magnifyingglass",
                title: "YouTube & SoundCloud Search",
                body: "The Search tab lets you search YouTube and SoundCloud by title, artist, or paste a full playlist URL. Search results show thumbnail, title, artist, and duration. Tap the play button to stream a track immediately or the download button to save it to your local library. Pasting a YouTube playlist URL fetches the full track list so you can download the entire playlist at once."
            ),
            HelpTopic(
                icon: "waveform",
                title: "Audio Format Preference",
                body: "The Audio Format picker in Settings → Streaming controls which container is requested when streaming or downloading: Opus (best quality per kilobyte, default), MP3 (maximum compatibility), AAC, or Best Available. Opus is recommended for most networks. Use MP3 if you have trouble playing a downloaded track."
            ),
        ]),
        HelpCategory(icon: "person.crop.circle", title: "Account", topics: [
            HelpTopic(
                icon: "icloud",
                title: "What Gets Synced",
                body: "Your Lumisound account syncs your favourites list, playlists (names, track order, and membership), audio settings (EQ, speed, pitch, crossfade, etc. — including any per-track overrides), and your accent colour to the server. This lets you restore everything after reinstalling the app or switching to a new device. The actual audio files are not uploaded — only the metadata and preferences."
            ),
            HelpTopic(
                icon: "arrow.up.to.cloud",
                title: "Push Sync",
                body: "A push sync writes your current favourites, playlists, and audio settings up to the server. Pushes happen automatically in the background a few seconds after any change so you normally do not need to trigger them manually. The Account screen shows the last sync time and provides a manual Push button if you want to force an immediate upload."
            ),
            HelpTopic(
                icon: "arrow.down.from.cloud",
                title: "Pull Sync",
                body: "A pull sync downloads your saved state from the server and merges it into what's already on the device — favourites and playlists missing locally are added, but nothing local is ever removed or overwritten by an older server copy, so the two sides simply converge. Pull happens automatically the moment you sign in or create an account, and again on every app launch while you are signed in — so switching accounts on the same device immediately loads that account's library state, badges, and Appearance settings. You can also trigger a manual pull from the Account screen, or from the Library tab's refresh button."
            ),
            HelpTopic(
                icon: "arrow.counterclockwise",
                title: "After Reinstall",
                body: "After reinstalling Lumisound, sign in with the same account and the app will automatically pull your favourites, playlists, and settings from the server. Your local audio files will not be restored automatically — you will need to re-scan Apple Music or re-import transferred files. Any streaming downloads that were saved to the app's Documents folder will also be gone and need to be re-downloaded."
            ),
            HelpTopic(
                icon: "clock.arrow.circlepath",
                title: "Backup History",
                body: "Every time your data syncs to the server, the server automatically saves a snapshot of your favourites, playlists, and settings beforehand. If something ever goes wrong with a sync, open Account → Backup History to see recent snapshots and restore one — your current state is backed up first, so a restore can always be undone."
            ),
            HelpTopic(
                icon: "icloud.and.arrow.up",
                title: "Cloud Backup (Uploaded Tracks)",
                body: "Library → Cloud Backup uploads your locally-imported tracks to your account's cloud storage so they survive a reinstall — open Cloud Backup after signing back in to restore them. Use the trash icon in the Uploaded Tracks header to delete everything you've previously uploaded; you'll be asked to confirm, and the count of tracks to be removed is shown in the confirmation. This only removes the cloud copies — your local files are untouched."
            ),
            HelpTopic(
                icon: "ladybug",
                title: "Report a Bug",
                body: "Account → Report a Bug lets you describe an issue, pick a category, and optionally leave a contact email. Your device model, iOS version, and the app version are filled in automatically so the developer can reproduce issues faster — you don't need to look these up yourself. Recent log entries are attached automatically to help with diagnosis. Tap Send to submit; you'll see a confirmation once it's received."
            ),
            HelpTopic(
                icon: "sparkles",
                title: "Discover & Listening Activity",
                body: "Account → Discover shows a Trending list of popular tracks and an Activity feed of what other users are listening to right now. To appear in either, turn on \"Share Listening Activity\" in your Account settings — this shares only song titles and artists from your play history, never file contents, URLs, or anything else. The toggle is off by default."
            ),
            HelpTopic(
                icon: "bell",
                title: "Notifications",
                body: "Account → Notifications is your inbox for server-generated updates: new achievement badges, new uploads from artists you follow, and activity on playlists you collaborate on. A badge on the Account tab and the Notifications row shows your unread count. Tap a notification to mark it read; pull to refresh for the latest."
            ),
            HelpTopic(
                icon: "key.viewfinder",
                title: "Discord Rich Presence",
                body: "Account → Discord Rich Presence sets up the companion Discord Rich Presence daemon — a small script you run on your own computer that shows \"Listening to <song> by <artist>\" on your Discord profile while Discord is open. Two steps: (1) Generate a setup token and paste it into the daemon's config as \"access_token\" — no Lumisound password needed, and it can be revoked any time from Account → Active Sessions (\"Discord RPC Bridge\"). (2) Enter your Discord Application's Client ID (and optional Rich Presence art asset name) and save — this is registered to your account, so the daemon fetches it automatically and there's nothing else to configure locally. Each user runs their own copy of the daemon with their own token, so everyone's Discord presence reflects their own listening — this is how Discord accounts are \"linked\" per user. The daemon clears your presence automatically when playback is paused or idle."
            ),
            HelpTopic(
                icon: "message",
                title: "Discord Webhook (Now Playing posts)",
                body: "Account → \"Now Playing Webhook\" is separate from Rich Presence: it posts a one-time message to a Discord channel via an incoming webhook whenever you start a new track, so a server can have a shared \"now playing\" feed. Create an incoming webhook in your Discord server under Channel Settings → Integrations → Webhooks, paste the URL in, and toggle it on or off at any time."
            ),
        ]),
        HelpCategory(icon: "person.2.fill", title: "Playlists & Sharing", topics: [
            HelpTopic(
                icon: "folder",
                title: "Playlist Folders & Tags",
                body: "Open a playlist and tap the folder icon to file it into a folder (existing or new, just type a name) and attach free-form tags. The Playlists tab groups playlists by folder automatically — playlists without a folder appear at the top. Tags are shown on the playlist detail screen and can be used to keep related playlists organised, e.g. by mood or project."
            ),
            HelpTopic(
                icon: "person.2.badge.gearshape",
                title: "Collaborative Playlists",
                body: "From a playlist, tap Share to generate a share code or link and invite other Lumisound users as Editors (can add/remove songs) or Viewers (read-only). Anyone with the code can open Collaborative Playlists → Enter Share Code to import it. You can revoke a share link at any time, which immediately cuts off access for everyone using it."
            ),
            HelpTopic(
                icon: "tray.and.arrow.down",
                title: "Shared with Me",
                body: "Playlists → Shared with Me lists every playlist another user has added you to as a collaborator, along with your role (Editor/Viewer) and the owner's username. Tap one to view its tracks, play them all, or save a local copy into your own library. Updates from the owner or other collaborators appear automatically the next time you open it."
            ),
            HelpTopic(
                icon: "arrow.triangle.2.circlepath",
                title: "Queue Sync",
                body: "While signed in, your \"Up Next\" queue is saved to the server in the background as it changes, and restored automatically when you open the app on another signed-in device — so you can pick up the same playback queue on your phone and iPad. Only track identifiers and titles are stored, not audio."
            ),
        ]),
        HelpCategory(icon: "sparkles", title: "Achievements & Discovery", topics: [
            HelpTopic(
                icon: "trophy",
                title: "Achievements & Streaks",
                body: "Account → Achievements tracks your listening streaks (consecutive days with at least one play), total plays, and total listening time, and unlocks badges as you hit milestones for play counts, hours listened, and streak lengths — plus a few special badges like Night Owl and Early Bird for listening at certain times of day. Badges are computed entirely server-side from your play history; there's nothing to configure."
            ),
            HelpTopic(
                icon: "wand.and.stars",
                title: "Discover Mix",
                body: "Account → Discover → Discover Mix is a personalised list of tracks seeded from the artists you listen to most, automatically excluding anything already in your library or favourites. Tap Play All to queue the whole mix, or play/queue individual tracks. It refreshes as your listening history grows."
            ),
            HelpTopic(
                icon: "person.crop.circle.badge.plus",
                title: "Artist Subscriptions",
                body: "Account → Subscriptions lets you follow a YouTube or SoundCloud channel/playlist URL by pasting it in and tapping Subscribe. Lumisound checks followed channels for new uploads in the background on a schedule iOS controls (so timing varies — it's not instant), plus any time you tap \"Check Now\". When new tracks appear you get a notification and can play or queue them straight from the Subscriptions screen."
            ),
            HelpTopic(
                icon: "music.note.list",
                title: "Scrobbling (Last.fm / ListenBrainz)",
                body: "Account → Scrobbling links your Last.fm and/or ListenBrainz account so finished tracks are submitted automatically. For Last.fm, tap \"Open Last.fm to Authorize\" to approve access in Safari, then return to the app to complete the link. For ListenBrainz, paste your user token from your ListenBrainz profile settings. Use the top toggle to pause scrobbling without unlinking either service."
            ),
        ]),
        HelpCategory(icon: "play.circle.fill", title: "Now Playing", topics: [
            HelpTopic(
                icon: "circle.fill",
                title: "Artwork Styles",
                body: "The artwork style picker at the top of the Now Playing screen lets you switch between 12 visual presets for the album art: Vinyl Disc (spinning record with the artwork printed in the centre, stops when paused), Album Art (a reflective, flipped-mirror card beneath the artwork), Polaroid (instant-photo frame with film grain and a curled corner), Floating Cards (palette-derived glow blobs drifting behind layered cards), Minimalist (trimmed reflection with a clean typography block), Glassmorphism (frosted glass panel), Retro CRT (scanlines and a CRT glow), Spectrum (animated bars with a colour-matched reflection), Cassette (spinning tape reels with a sepia, grainy texture), Neon Glow (layered neon tube outline that pulses with playback), Aura Glow (a slowly rotating colour aura pulled from the artwork), and Tilt Card (drag the artwork for a 3D tilt with a synced reflection). Your choice is saved and persists between sessions."
            ),
            HelpTopic(
                icon: "waveform.badge.clock",
                title: "Timeline & Seeking",
                body: "The timeline slider shows your current position in the track. Drag the thumb to scrub to any point; the elapsed and remaining time labels update in real time while you drag. Release to confirm the seek. The slider is disabled while the duration is unknown (for example at the very start of a stream)."
            ),
            HelpTopic(
                icon: "heart",
                title: "Favourite Button",
                body: "The heart icon to the right of the track title toggles the current song as a favourite. Favourited songs appear in the Favorites tab in the Library and are included in synced account data. The heart fills with the accent colour when active and springs with a subtle animation on tap."
            ),
            HelpTopic(
                icon: "list.number",
                title: "Up Next Queue",
                body: "The Up Next panel shows the next 10 songs in the queue as a horizontal scroll of artwork thumbnails. The first thumbnail has an accent-coloured border to indicate it plays next. Tap any thumbnail to jump straight to that song. The badge on the panel header shows total queue length and a shuffle icon appears when shuffle is enabled."
            ),
            HelpTopic(
                icon: "quote.bubble",
                title: "Lyrics",
                body: "Tap the lyrics icon on the Now Playing screen to show synced lyrics, if available, in a scrolling panel above the playtime counter. The current line is highlighted and the view auto-scrolls to follow playback; scrolling only animates while a track is playing, and pausing or resuming snaps the view back to the correct line instantly without overshooting."
            ),
        ]),
        HelpCategory(icon: "apps.iphone", title: "Widgets", topics: [
            HelpTopic(
                icon: "apps.iphone",
                title: "Adding the Widget",
                body: "Long-press the Home Screen or Lock Screen until the icons jiggle, then tap the + button in the top-left corner. Search for \"Lumisound\" in the widget gallery. Choose between the small (1×1) or medium (2×1) size and tap Add Widget. The widget is live and updates automatically whenever the currently playing track changes."
            ),
            HelpTopic(
                icon: "music.note",
                title: "What It Shows",
                body: "The Lumisound widget displays the album artwork, song title, and artist name for the currently playing track. It refreshes through the Darwin notification bridge so changes appear within a second or two of the track changing. If nothing is playing the widget shows the Lumisound logo and a prompt to open the app."
            ),
            HelpTopic(
                icon: "lock.iphone",
                title: "Lock Screen vs Home Screen",
                body: "The Lock Screen widget is a smaller inline or accessory rectangular format that shows the song title and artist in a compact single line. The Home Screen widget is the standard rounded-corner square that shows artwork alongside the track info. Both support Dark Mode and adapt to the current accent colour set in Appearance settings."
            ),
        ]),
    ]
}

// MARK: - SettingsHelpDetailView

private struct SettingsHelpDetailView: View {
    let category: HelpCategory

    var body: some View {
        List {
            Section {
                ForEach(category.topics) { topic in
                    helpRow(icon: topic.icon, title: topic.title, body: topic.body)
                }
            }
            .listRowBackground(AppTheme.surface)
        }
        .scrollContentBackground(.hidden)
        .background(GalleryBackgroundView().ignoresSafeArea())
        .navigationTitle(category.title)
        .navigationBarTitleDisplayMode(.large)
        .toolbarBackground(.hidden, for: .navigationBar)
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
