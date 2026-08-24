# tvOS: What Was Skipped and Why

Companion to `TVOS_WATCHOS_FEASIBILITY.md` (the original planning doc). This
covers the 4-round tvOS upgrade (2026-08-24) and is honest about what
*wasn't* built — split into two categories that get very different treatment
if this is ever revisited:

- **Not possible** — a real platform/architecture wall. Building it means a
  separate, large project (rewriting the player, or waiting on Apple), not
  "spend more time on it."
- **Possible, deliberately skipped** — the bridge endpoint or technique
  exists and would work. Skipped because it didn't fit tvOS's constraints
  (no local file library), wasn't worth the port cost for what it adds, or
  is a poor fit for a Siri-Remote-driven 10-foot screen. Any of these could
  be picked back up later without new research.

---

## Not possible

### Full parametric EQ
iOS's equalizer is an `AVAudioUnitEQ` node wired into an `AVAudioEngine`
graph (`AudioPlayerManager.swift`). tvOS's client streams through a plain
`AVPlayer`, which has no mixer graph to attach an EQ node to. The only real
paths in:
- Rewrite the tvOS player onto `AVAudioEngine` (a large, separate
  architecture change — this client was deliberately kept on `AVPlayer` for
  simplicity).
- `MTAudioProcessingTap` — pull raw sample buffers off the AVPlayer item and
  run hand-written biquad filters. Real DSP work, not a UI feature.

Neither is "more time," both are separate projects.

### Listen Together
iOS's version (`SharePlayCoordinator.swift`, `ListenTogetherActivity.swift`)
is genuine Apple SharePlay/`GroupActivities`, anchored to a FaceTime call.
There is no supported path for a third-party, non-video-conferencing tvOS
app to originate or join a `GroupSession` the way this feature needs. This
is an Apple platform boundary, not a missing integration — confirmed via
direct source inspection, not guessed.

---

## Possible, deliberately skipped

### 22 of 24 Now Playing artwork styles
Only Circuit Pulse and Radar Sweep were ported. The other 22 read from
`Song`/`LibraryManager`/live palette extraction (`ArtworkPaletteLoader`,
`ArtworkColorExtractor`) that don't exist on tvOS's much smaller client —
porting them means also porting those dependencies, for a purely cosmetic
feature. The 2 that shipped were picked specifically because they're
self-contained SwiftUI/Canvas with no such dependency.

**To revisit:** pick more candidates from `ios/Lumisound/Sources/Views/
*ArtworkView.swift`, check each for `Song`/`LibraryManager`/palette
references the same way, and either simplify those away (like Circuit
Pulse's palette → static accent color) or port a lightweight palette
extractor for tvOS off `UIImage` (`TVAuthImage` already loads one).

### Password change / 2FA setup / account deletion
All three bridge endpoints exist and work
(`POST /auth/change-password`, `/auth/2fa/setup`, `/auth/delete-account`).
Skipped because typing a password or scanning a 2FA QR code via a Siri
Remote is a genuinely bad experience — better done on phone or web, where
the account already has this UI.

### Full friend-request flow
Search/add/accept/decline/block friends are all plain REST
(`/api/social/friends/*`). Skipped in favor of a minimal read-only "Friends
Listening Now" card because a shared living-room screen showing your whole
social graph and incoming friend requests is a worse fit than a personal
phone — the room, not just the account holder, sees it. What shipped only
ever renders when a friend is actually playing something right now, and has
no way to add/manage anyone from the TV.

### Subscription management (auto-download, folder settings)
The subscription *feed* (new uploads from channels you follow) is built and
read-only. Creating/editing subscriptions, and especially their
auto-download-to-a-folder setting, depends on the local file library iOS has
that tvOS structurally doesn't — there's no folder to download into.

### iOS's on-device Lua smart-playlist / mood-playlist engines
`LuaSmartPlaylistEngine.swift` and `MoodPlaylistService.swift` both filter
over `LibraryManager.allSongs` (the on-device library scan) — not portable
to tvOS as-is. Used the bridge's separate, genuinely-server-side BPM-bucket
equivalent (`GET /user/music/smart-playlists`) instead, which produces the
same 4-mood-bucket shape from server-stored BPM. Not a port of the Lua rule
engine or its custom rule-builder UI — just the one fixed BPM-bucket
grouping the bridge already computes.

### Push notification registration (APNs)
No device push-token registration was added — tvOS has no APNs setup here.
The notification *inbox* (`GET /user/notifications`) is a separate, fully
decoupled plain-REST feature and was built; a notification only shows up
when the TV app is opened and polls, not as a push banner.

### Per-badge achievement detail sheets
The Stats screen shows the full badge catalog (title + icon + locked/
unlocked), ported from `AchievementsView.swift`'s `allBadges`. iOS's
tap-to-see-the-unlock-requirement detail sheet wasn't ported — first-pass
scope call, not a technical blocker.

---

## Where this fits in the bigger picture

Everything above was scoped against the [round 1–4 build](TVOS_WATCHOS_FEASIBILITY.md)
that took tvOS from a ~1,500-line minimal client to a full-featured app:
core playback/library, Now Playing richness, discovery/smart features, and
social/account depth. See git log for `LumisoundTV` commits for the full
build history.
