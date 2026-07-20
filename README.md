<p align="center">
  <img src="ios/Lumisound/Resources/Assets.xcassets/AppIcon.appiconset/Icon-1024.png" width="120" alt="Lumisound icon">
</p>

<h1 align="center">Lumisound</h1>

<p align="center">
  A full-featured, privacy-respecting iOS music player — stream from YouTube and SoundCloud,
  manage a personal cloud library, apply spatial 8D audio and a 10-band EQ, and sync
  everything across devices with a free account.
</p>

---

## Repository layout

| Path | What it is |
|---|---|
| [`ios/`](ios) | The Lumisound iOS app (SwiftUI + AVFoundation) — install instructions, build steps, full feature docs |
| [`ios-bridge/`](ios-bridge) | FastAPI server powering search/streaming, account sync, and all server-side features below |
| [`discord-rpc/`](discord-rpc) | Optional local daemon that mirrors your "now playing" to Discord Rich Presence |

See [`ios/README.md`](ios/README.md) for installation (AltStore / Sideloadly), self-hosting the
bridge, and build-from-source instructions.

---

## Features

### Playback & Audio

| Feature | Details |
|---|---|
| **Playback** | Gapless, crossfade, A–B repeat, sleep timer, variable speed & pitch, auto-radio |
| **Audio FX** | 10-band EQ with presets, 23 effects (8D spatial audio, bass boost, tremolo, vibrato, nightcore, vaporwave, karaoke vocal removal…), real-room reverb (on by default, adjustable room/mix) |
| **Per-Track Sound** | Pin EQ/effects/volume overrides to a specific song |
| **ReplayGain & Volume Boost** | Loudness normalisation plus up to 200% volume with a limiter |
| **Now Playing** | 25 selectable visual styles for the album art (vinyl, cassette, aurora, glitch/VHS, and more), plus a built-in editor to design and save your own; full transport controls, Up Next queue, lock-screen & headphone controls |
| **Widgets** | Home Screen and Lock Screen widgets showing the current track |

### Library

| Feature | Details |
|---|---|
| **Home dashboard** | The Library tab opens on a customizable dashboard — Quick Access shortcuts, Weekly Mix, Mixes, Recently Added, On Repeat, Genres, Moods, Forgotten Favorites, On This Day, Friends Activity, and more. Reorder or hide any shelf, set a custom greeting, and pick a dashboard-only accent color |
| **Local files** | Import from the Files app, drag-and-drop on iPad, watched folders auto-rescanned on launch |
| **Apple Music library** | Scan and play your existing iTunes/Apple Music library on-device |
| **Folder/album organisation** | Albums derived from directory names; list, 2-col, and 3-col grid layouts |
| **Playlist folders & tags** | File playlists into folders and attach free-form tags to keep things organised |
| **M3U import/export** | Bring in a `.m3u`/`.m3u8` playlist from another app (matched by filename, falling back to title/artist), or export any playlist as one |
| **Downloads manager** | See every downloaded track's on-disk size, sort by size or date, and delete individually or in bulk |
| **Duplicate & corrupt file finders** | Duplicate Finder groups likely-duplicate downloads by matching how they actually sound, not just title text; Corrupt File Finder flags any download that fails to play so you can re-fetch just that one |
| **Aria Lumi metadata matching** | Built-in, always on — when a local file has more than one possible metadata match, Aria Lumi (Lumisound's own music intelligence) reviews the candidates using titles, artists, cover art, and a sense of your own listening habits to pick the right one instead of a plain "first result" guess, and learns from any corrections you make |

### Streaming (via the bridge server)

| Feature | Details |
|---|---|
| **Search & stream** | YouTube and SoundCloud search, with playlist/album URL resolution (up to 50 tracks) |
| **Spotify link import** | Paste a Spotify track/album/playlist link — the bridge reads public Spotify metadata only (never audio, which Spotify DRM-protects) and matches each track to a playable YouTube result. Requires the server operator to set `SPOTIFY_CLIENT_ID`/`SPOTIFY_CLIENT_SECRET` |
| **Downloads** | Save streamed tracks to your local library with format choice (Opus, MP3, AAC, Best) |
| **Background downloads & Pending Imports** | Downloads keep running server-side even if you close the app; a Pending Imports screen (Cloud Services menu) shows what's finished and waiting, which folder it's headed for, and lets you override the folder or import on demand |
| **Personal Cloud Library** | Upload your own files to a private server folder; play and manage from any device |
| **Discover Mix** | A personalised mix seeded from your most-played artists, excluding anything you already have |
| **Trending & Activity** | See what's popular and what other opted-in users are playing right now |
| **Artist Subscriptions** | Follow YouTube/SoundCloud channels — get notified and queue new uploads automatically |

### Account & Sync

| Feature | Details |
|---|---|
| **Free accounts** | Username/password, no email required — sync playlists, favourites, settings, and play history |
| **Push/pull sync** | Background sync on every change and app launch; pull merges rather than overwrites |
| **Backup history** | Automatic pre-sync snapshots you can restore from |
| **Queue sync** | Your Up Next queue is saved server-side and restored on other signed-in devices |
| **Achievements** | Listening streaks, play-count and listening-time badges, time-of-day badges |
| **Notifications** | In-app inbox for achievement unlocks, subscription uploads, and collaborator activity — delivered as real background push when the server operator configures an APNs key (`APNS_KEY_BASE64`/`APNS_KEY_ID`/`APNS_TEAM_ID`), otherwise surfaced on next foreground/poll |

### Sharing & Social

| Feature | Details |
|---|---|
| **Friends & profiles** | Add friends, accept/decline requests, and view a friend's public profile — banner, avatar, bio, pinned tracks, and live online/now-playing status if they share it. Your own Profile tab shows the same public view with an Edit button, rather than opening straight into editing |
| **Collaborative playlists** | Share a playlist via code/link; invite others as Editor or Viewer, revoke anytime |
| **Shared with Me** | View, play, or save a local copy of playlists others have shared with you |
| **Scrobbling** | Link Last.fm and/or ListenBrainz to scrobble finished tracks automatically |
| **Discord Webhook** | Post a "Now Playing" message to a Discord channel via incoming webhook |
| **Discord Rich Presence** | Generate a per-user token and register your Discord Application Client ID in-app; the [local Rich Presence daemon](discord-rpc) picks up both automatically and shows "Listening to X by Y" on your Discord profile while Discord is open |

### Privacy

- No third-party analytics or crash reporting.
- Account data (playlists, settings, history) lives only on the bridge server you connect to.
- Apple Music access is optional and read-only.
- "Share Listening Activity" (for Trending/Discover) is off by default and shares only titles/artists.
- **Aria Lumi** (Settings → Account → AI Features) — built into the app, always on, no opt-in toggle.
  For local files with more than one possible metadata match, titles/artists/albums/cover art for
  those candidates, plus a lightweight signal from your own play history and favorites (which artists/
  albums you actually listen to and how much, not full listening history), are sent to Google's Gemini API
  to pick the correct match instead of a plain "first result" guess, and she learns from any corrections
  you make. No audio or file contents are ever sent, and she never overrides an already-exact match by
  herself without reviewing the alternatives first.

---

## In-app help

The app includes a full **Help & Feature Guide** (Settings → Help) covering every feature above
in detail, with usage tips for each.

READ IT!!!

---

## License

MIT — see [LICENSE](LICENSE).
