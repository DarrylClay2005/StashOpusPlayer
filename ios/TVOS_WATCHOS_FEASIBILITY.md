# tvOS App + watchOS 15 Companion — Feasibility & Design Notes

Status: **research / planning only** (no targets or code added yet). This
documents what it would take to ship a tvOS app and a watchOS companion for
Lumisound, what's reusable from the existing iOS app, and a rough effort
estimate, so we can decide scope before scaffolding Xcode targets.

Current app baseline (from `ios/project.yml`): iOS 16 deployment target,
SwiftUI throughout, an `AVAudioEngine`-based `AudioPlayerManager`, a FastAPI
"bridge" backend (`ios-bridge/`) for streaming/download/sync, and per-user
accounts with JWT auth.

---

## 1. What's shareable vs. needs reimplementation

The codebase is SwiftUI + a handful of services, which ports far better than a
UIKit app would. Breakdown by layer:

| Layer | File(s) | tvOS | watchOS |
|---|---|---|---|
| **Models** (`Song`, `Playlist`, `AudioSettings`, `StreamTrack`, sync DTOs) | `Sources/Models/*`, parts of `Services/*` | ✅ reuse as-is | ✅ reuse as-is |
| **Networking** (`StreamingService`, `AccountService`, `NetworkRetry`) | `Sources/Services/*` | ✅ reuse (URLSession is cross-platform) | ✅ reuse |
| **Audio engine** (`AudioPlayerManager`, effects, EQ, reverb, crossfade) | `Sources/Services/AudioPlayerManager.swift` | ✅ AVAudioEngine works on tvOS | ⚠️ watchOS supports AVAudioEngine but local playback on-wrist is unusual; the realistic watch role is **remote control + handoff**, not hosting the full engine |
| **Artwork / palette / BPM** services | `Sources/Services/*` | ✅ reuse | ⚠️ heavy analysis (BPM/loudness) should stay off-watch |
| **Views** | `Sources/Views/*` | ❌ rebuild — tvOS uses the focus engine; touch gestures, `.searchable`, swipe actions, sheets all differ | ❌ rebuild — tiny screen, Digital Crown, glanceable UI |
| **Now Playing artwork styles** (18 styles) | `Sources/Views/*ArtworkView.swift` | ⚠️ a subset could be reused on the big screen; most are tuned for phone sizing | ❌ not applicable |
| **UIKit bits** (`DocumentPicker`, haptics `UIImpactFeedbackGenerator`, `MPMediaLibrary`) | various | ❌ unavailable/different on tvOS | ❌ unavailable; use `WKInterfaceDevice` haptics |

Rule of thumb: **~60–70% of the non-UI code reuses cleanly**, all UI is new.

---

## 2. tvOS app

### Capabilities & constraints
- **Focus engine**: navigation is remote/focus-driven, not touch. Lists,
  buttons, and the now-playing transport must be focusable and laid out for
  10-foot viewing. SwiftUI handles focus automatically but layouts need
  rethinking (large type, horizontal shelves).
- **No `MPMediaLibrary`**: there's no Apple Music local library on tvOS, so the
  "Apple Music transfer" import path doesn't apply. tvOS is **streaming/bridge
  + per-user cloud library only** — which actually simplifies it.
- **No document picker / Files import** in the same form; rely on the bridge's
  per-user music + YouTube/SoundCloud download flows.
- **Storage**: tvOS apps get limited on-device storage and the system can purge
  it; treat all downloads as cache. The per-user cloud library (already built)
  is the natural source of truth here.
- **Audio**: `AVAudioEngine` + the existing effects chain work. Background audio
  + the now-playing info center / Siri Remote transport integrate via
  `MPRemoteCommandCenter` (already used).

### Effort estimate
- New Xcode target (`platform: tvOS`, shared sources for Models/Services).
- Rebuild ~6 core screens for the focus engine: Library, Now Playing, Search/
  Download, Playlists, Account, Settings. Reuse all services unchanged.
- **Estimate: ~2–3 weeks** for a focused v1 (library browse, playback,
  search/download, account sync). The shared service layer removes most of the
  risk; the work is UI + focus tuning.

### App Store / entitlements
- Separate tvOS build of the same app (can share the bundle ID family). Needs
  its own App Store screenshots/metadata.
- Background audio entitlement (`UIBackgroundModes: audio`) as on iOS.
- The existing App Group (`group.com.lumisound.ios`) can be extended to tvOS if
  shared defaults are wanted, but tvOS↔iOS don't share storage automatically.

---

## 3. watchOS 15 companion

> Note: "watchOS 15" tracks the iOS-19-era OS generation. Whatever the current
> watchOS at build time, the design below is version-agnostic; nothing here
> depends on a feature newer than watchOS 10.

### Realistic role: **remote + glance**, not a full player
Hosting the entire `AVAudioEngine` effects chain on-wrist is technically
possible but a poor fit (battery, the watch rarely outputs audio directly). The
high-value companion is:
1. **Now Playing remote** — show current track + artwork, play/pause, skip,
   scrub, favorite, volume via the Digital Crown. Drives the phone's
   `AudioPlayerManager` over **WatchConnectivity** (`WCSession`).
2. **Glances / complications** — current track on the watch face; tap to open.
3. **Quick library/playlist browse** with "play on phone".
4. (Optional, later) **On-watch playback** of downloaded tracks for phone-free
   listening via AirPods — a separate, larger effort using `AVAudioPlayer` +
   the bridge's per-user library.

### What's needed
- New watchOS app + extension target.
- A small `WCSession` message protocol between phone and watch: the phone
  publishes now-playing state (title/artist/artwork thumbnail/isPlaying/
  position) and accepts commands (play/pause/next/prev/seek/favorite). This is
  new code on **both** sides — the iOS app needs a `WatchConnectivity` bridge
  added to `AudioPlayerManager`.
- Reuse Models + a trimmed `AccountService` for auth/sync if doing independent
  browse.
- Complication via WidgetKit (the app already has a `LumisoundWidget` target to
  model the approach on).

### Constraints
- Artwork must be downscaled hard before sending over `WCSession` (send a
  ~120px thumbnail, not full art).
- `WCSession` reachability is intermittent; the watch UI must degrade to "not
  connected" gracefully.
- Background execution on watchOS is tightly limited; the remote updates while
  the app/complication is active and via background `WCSession` transfers.

### Effort estimate
- **Remote + complication v1: ~2 weeks** (most of it is the `WCSession`
  protocol on both sides + a handful of glanceable screens).
- **On-watch independent playback: +2–3 weeks** (separate playback path,
  download management, sync) — recommend deferring to a later phase.

---

## 4. Recommended sequencing
1. **tvOS first** — biggest reuse of the existing service layer, no new
   cross-device protocol, immediately useful on the big screen.
2. **watchOS remote** — needs the new `WCSession` bridge in the iOS app; ship
   the remote/complication before considering on-watch playback.
3. **watchOS independent playback** — only if there's demand; it's effectively
   a third small player implementation to maintain.

## 5. Open decisions for the user
- tvOS: streaming/cloud-library only (recommended) vs. also trying to mirror
  on-device downloads?
- watchOS: remote-only v1 (recommended) vs. invest up front in on-watch
  playback?
- Shared bundle ID family + unified App Store listing vs. separate listings?
