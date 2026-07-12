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
| **Now Playing** | Vinyl disc or album-art view, full transport controls, Up Next queue, lock-screen & headphone controls |
| **Widgets** | Home Screen and Lock Screen widgets showing the current track |

### Library

| Feature | Details |
|---|---|
| **Local files** | Import from the Files app, drag-and-drop on iPad, watched folders auto-rescanned on launch |
| **Apple Music library** | Scan and play your existing iTunes/Apple Music library on-device |
| **Folder/album organisation** | Albums derived from directory names; list, 2-col, and 3-col grid layouts |
| **Playlist folders & tags** | File playlists into folders and attach free-form tags to keep things organised |
| **Aria Lumi metadata matching** | Optional (Settings → Account → AI Features, off by default) — when a local file's metadata is ambiguous, Aria Lumi picks the correct match instead of a plain "first result" guess, and learns from any corrections you make |

### Streaming (via the bridge server)

| Feature | Details |
|---|---|
| **Search & stream** | YouTube and SoundCloud search, with playlist/album URL resolution (up to 50 tracks) |
| **Spotify link import** | Paste a Spotify track/album/playlist link — the bridge reads public Spotify metadata only (never audio, which Spotify DRM-protects) and matches each track to a playable YouTube result. Requires the server operator to set `SPOTIFY_CLIENT_ID`/`SPOTIFY_CLIENT_SECRET` |
| **Downloads** | Save streamed tracks to your local library with format choice (Opus, MP3, AAC, Best) |
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
| **Notifications** | In-app inbox for achievement unlocks, subscription uploads, and collaborator activity |

### Sharing & Social

| Feature | Details |
|---|---|
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
- **AI-Assisted Suggestions** (Settings → Account → AI Features) — off by default. When enabled, track
  titles/artists/genres for ambiguous local files may be sent to Anthropic's API (powering "Aria Lumi",
  the bridge's music intelligence) to improve metadata matching, with more suggestions planned. No audio
  or file contents are ever sent, and the feature never overrides a confident local match.

---

## In-app help

The app includes a full **Help & Feature Guide** (Settings → Help) covering every feature above
in detail, with usage tips for each.

READ IT!!!

---

## License

MIT — see [LICENSE](LICENSE).
