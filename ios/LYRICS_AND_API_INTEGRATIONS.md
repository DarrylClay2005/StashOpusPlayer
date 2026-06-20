# Lyrics (Genius) & Other Beneficial API Integrations — Research

Status: **research / planning only** (no code changes). Evaluates the Genius
API for lyrics and surveys other APIs that could improve Lumisound.

## Current lyrics stack (for context)
- **Primary**: `lrclib.net` — free, no key, returns **time-synced LRC** lyrics.
  Used both client-side (`NowPlayingView.syncedLyricsURL` →
  `lrclib.net/api/get` + `/api/search`) and server-side (`/api/lyrics` in
  `ios-bridge/main.py`).
- **Fallback**: `lyrics.ovh` (`fetchLyricsOVH`) — free, no key, **plain text
  only** (no timing).
- **Manual**: `LyricsSyncEditorView` lets users paste + time-sync their own LRC.

This is already a solid, keyless, synced-first setup. The question is whether
Genius adds value on top of it.

---

## 1. Genius API — the critical caveat

**Genius's official API does NOT return raw lyrics text.** This is the single
most important fact for this task:

- The API (`api.genius.com`) exposes **songs, artists, annotations, and
  referents** — metadata and crowd-sourced annotations — but **not** the full
  lyric body. Genius deliberately withholds lyric text from the API for
  licensing reasons.
- Apps that show "Genius lyrics" obtain the text by **scraping the public song
  web page** (the HTML at the `url` the API returns), which is:
  - Against Genius's Terms of Service,
  - Fragile (page markup changes break it), and
  - Legally riskier than using a licensed/he community source.

**Conclusion:** Genius is **not a good fit as a lyrics-text source.** lrclib
(synced) + lyrics.ovh (plain) already cover that better and legitimately.

### Where Genius *could* still add value (legitimately)
Using only what the API actually returns:
- **Rich song metadata**: canonical title/artist, album, release date, producer/
  writer credits, primary artist image — useful for the metadata-enrichment
  chain and artist photos.
- **"Song facts" / annotations**: a "Story behind the song" panel in Now Playing
  using `referents`/`annotations` (these *are* API-provided and licensed for
  this use).
- **Search disambiguation**: Genius search is good at resolving messy
  YouTube-style titles ("Song (Official Video) [feat. X]") to a clean
  artist/title pair — handy for improving lrclib match rates and the duplicate
  finder's normalization.

### Auth & limits (if pursued for metadata/annotations only)
- OAuth2 / a free **Client Access Token** (no user login needed for public
  read). Token stored server-side in the bridge (mirror the existing per-user
  YouTube key pattern, or a single server-wide token).
- Rate limits are not officially published but are modest; cache aggressively
  (the bridge already has caching patterns). Add a `genius_token` server env
  var, not a per-user key, since this is metadata not personal data.

**Recommendation:** *Optionally* add Genius for a "Song Story" annotations panel
and as a metadata/disambiguation helper — **not** as a lyrics-text provider.
Lower priority than the items below.

---

## 2. Better lyrics coverage without Genius
- **Musixmatch** (has an official API with *licensed* lyric text + synced
  lyrics) — but it requires a paid commercial plan for full lyrics and has
  strict display rules. Highest-quality option if a budget exists; key-gated.
- **NetEase / QQ Music** community LRC sources — large synced-lyric coverage
  for non-Western catalogs where lrclib is sparse. Keyless but unofficial.
- **Keep lrclib primary**; consider adding NetEase as a *third* fallback after
  lyrics.ovh to improve coverage for K-pop/J-pop/C-pop where lrclib misses.

---

## 3. Other APIs that would benefit the app (ranked)

1. **MusicBrainz + Cover Art Archive** *(keyless, high value)*
   - Canonical artist/release/recording metadata and high-quality cover art.
   - Already being added for **artist images** (see `ArtistImageService`
     MusicBrainz→Wikimedia fallback this round). Extend it to fill
     album/release metadata gaps and as another cover-art source.

2. **AcoustID / Chromaprint** *(keyless ID, key for lookups)*
   - **Audio fingerprinting** → identify untagged local files by their actual
     audio, then fetch correct metadata from MusicBrainz. Would dramatically
     improve "Force Metadata Sync" for files with no/garbage tags. Bigger lift
     (needs the Chromaprint fingerprint computed on-device or on the bridge).

3. **Deezer API** *(keyless, already used)*
   - Already the primary artist-image source. Also good for genre, BPM-ish
     "gain"/preview data, and album metadata — could feed Auto-EQ's genre
     detection (the genre-aware Auto EQ added this round benefits directly from
     better genre tags).

4. **Last.fm / ListenBrainz** *(key for Last.fm; ListenBrainz keyless)*
   - The app already has scrobbling (`ScrobblingView`). Last.fm additionally
     offers **similar-artists / recommendations** that could power a smarter
     "Auto-Radio" and Discover Mix than the current YouTube-mix approach.
     ListenBrainz is the open, keyless alternative.

5. **TheAudioDB** *(free key)*
   - Artist biographies, banners, fan art, album descriptions — nice-to-have
     content for richer Artist/Album detail screens.

---

## 4. Suggested priority
1. **MusicBrainz/Cover Art Archive expansion** — keyless, complements work
   already in flight, improves metadata + artwork coverage.
2. **AcoustID fingerprinting** — the highest-impact fix for bad/missing local
   metadata (powers a genuinely smart Force Metadata Sync), but the largest
   effort.
3. **Last.fm/ListenBrainz recommendations** — smarter Auto-Radio/Discover.
4. **Genius (annotations/metadata only)** — a "Song Story" panel + title
   disambiguation. Explicitly *not* for lyric text.
5. **NetEase LRC fallback** — only if non-Western lyric coverage is a priority.

Nothing here changes the current, working lrclib-first lyrics flow; these are
additive. Genius specifically should be set expectations-wise as a metadata/
annotations source, never a lyrics-text source.
