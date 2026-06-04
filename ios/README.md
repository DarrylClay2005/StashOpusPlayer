# Lumisound for iOS

A full-featured, privacy-respecting iOS music player built with SwiftUI and AVFoundation. Stream from YouTube and SoundCloud, manage your personal cloud library, apply spatial 8D audio and a 10-band EQ, and keep everything synced across devices with a free account.

---

## Features

| Category | Details |
|---|---|
| **Playback** | Gapless, crossfade, AB repeat, sleep timer, variable speed & pitch |
| **Audio FX** | 10-band EQ, 23 audio effects (8D spatial audio with speed control, nightcore, vaporwave, karaoke…) |
| **Library** | Local files, Apple Music library, folder/album organisation by directory name |
| **Streaming** | YouTube & SoundCloud search, stream, download — via bridge server |
| **Personal Cloud Library** | Upload your own audio files to your personal server folder; play & manage from anywhere |
| **Account** | Free accounts on the shared server — sync playlists, settings, play history, and favourites |
| **Visuals** | Gallery background (slideshow with transitions), vinyl disc artwork, lyric display |
| **Now Playing** | Full transport controls, Up Next queue, lock-screen & headphone controls |

---

## Installation (iOS — no Jailbreak required)

### Option A — AltStore (recommended for auto-updates)

1. Install [AltStore](https://altstore.io/) on your iPhone.
2. In AltStore → **Sources**, add:
   ```
   https://raw.githubusercontent.com/HeavenlyXenusVR/Lumisound/main/ios/altstore-source.json
   ```
3. Find **Lumisound** in the Browse tab and tap **Install**.
4. Updates appear automatically when a new version ships.

### Option B — Sideloadly / manual IPA

1. Download the latest `Lumisound-{version}-unsigned.ipa` from the [Releases page](https://github.com/HeavenlyXenusVR/Lumisound/releases/latest).
2. Install with [Sideloadly](https://sideloadly.io/), [AltServer](https://altstore.io/), or any IPA signer.

---

## The Bridge Server

Lumisound connects to a FastAPI bridge server that powers YouTube/SoundCloud search and streaming, the personal cloud library, and account sync.

### Where the server lives

The app ships pointed at the shared server running at:

```
https://germinate-props-motive.ngrok-free.dev
```

This is a static ngrok domain running on the developer's machine. It is always on and accessible from anywhere without home Wi-Fi. You do not need to run your own server to use Lumisound — just create a free account (see below).

### Creating your account

Accounts are created directly in the app:

1. Open **Lumisound** — on first launch the welcome prompt appears.
2. Tap **Create Account**, enter a username and password (email optional).
3. Your playlists, favourites, audio settings, and personal cloud library are now synced to the server.

To log in on another device: reopen the app → tap **Log In** → enter your credentials.

> **No email required.** Username and password are enough. You can add an email later in Settings → Account.

### Accessing your personal music library

After logging in, open **Search → My Library**. You can:

- Tap **Upload Music to Server** to send local audio files from your device to your personal folder.
- Organise files into subfolders — folder names become album names in the library view.
- Play, stream, or delete files directly from the app.

### Self-hosting the bridge server

If you want to run your own server (for a private instance or extra storage):

```bash
cd ios-bridge
cp .env.example .env          # fill in DB creds and JWT secret
docker compose up -d
```

Then in **Lumisound → Settings → Streaming** set the Bridge URL to your server address. Point `SERVER_MUSIC_DIR` and `USER_MUSIC_DIR` environment variables to your music directories.

See [ios-bridge/README.md](../ios-bridge) for full server configuration.

---

## Build from Source (macOS only)

```bash
# Prerequisites: Xcode, XcodeGen
brew install xcodegen

cd ios
xcodegen generate          # generates Lumisound.xcodeproj
open Lumisound.xcodeproj   # build from Xcode
```

Set your Apple development team in **Xcode → Signing & Capabilities** before archiving.

### CI / GitHub Actions

Push to `main` triggers the **Build iOS IPA** workflow (artifact only).  
Push a tag `ios/v*` (e.g. `ios/v1.3.0`) triggers the **Release iOS IPA** workflow which:
1. Stamps the version into `project.yml`
2. Builds and packages the unsigned IPA
3. Creates a GitHub Release with the IPA attached
4. Updates `altstore-source.json` automatically

---

## Privacy

- No analytics or crash reporting sent to third parties.
- Account data (playlists, settings) stored on the bridge server you connect to.
- Apple Music library access is optional and only used to display your local tracks.
- Streaming uses yt-dlp on the bridge server — no data is sent to Google or SoundCloud directly from the app.

---

## License

MIT — see [LICENSE](../LICENSE).
