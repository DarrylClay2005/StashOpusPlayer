CREATE TABLE IF NOT EXISTS ios_users (
    id VARCHAR(36) PRIMARY KEY,
    username VARCHAR(255) UNIQUE NOT NULL,
    email VARCHAR(255) UNIQUE,
    password_hash VARCHAR(255) NOT NULL,
    display_name VARCHAR(255),
    avatar_url TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    last_login TIMESTAMP NULL,
    is_active BOOLEAN DEFAULT TRUE
);

CREATE TABLE IF NOT EXISTS ios_user_sessions (
    token_id VARCHAR(36) PRIMARY KEY,
    user_id VARCHAR(36) NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    expires_at TIMESTAMP NOT NULL,
    device_name VARCHAR(255),
    INDEX idx_user_id (user_id),
    FOREIGN KEY (user_id) REFERENCES ios_users(id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS ios_user_playlists (
    id VARCHAR(36) PRIMARY KEY,
    user_id VARCHAR(36) NOT NULL,
    name VARCHAR(255) NOT NULL,
    description TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    INDEX idx_user_id (user_id),
    FOREIGN KEY (user_id) REFERENCES ios_users(id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS ios_playlist_tracks (
    id VARCHAR(36) PRIMARY KEY,
    playlist_id VARCHAR(36) NOT NULL,
    track_url TEXT,
    local_song_id VARCHAR(255),
    title TEXT NOT NULL,
    artist TEXT,
    album TEXT,
    duration_seconds INT DEFAULT 0,
    position INT DEFAULT 0,
    added_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_playlist (playlist_id),
    FOREIGN KEY (playlist_id) REFERENCES ios_user_playlists(id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS ios_user_favorites (
    user_id VARCHAR(36) NOT NULL,
    song_id VARCHAR(255) NOT NULL,
    title TEXT,
    artist TEXT,
    album TEXT,
    added_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (user_id, song_id),
    FOREIGN KEY (user_id) REFERENCES ios_users(id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS ios_play_history (
    id VARCHAR(36) PRIMARY KEY,
    user_id VARCHAR(36) NOT NULL,
    track_url TEXT,
    local_song_id VARCHAR(255),
    title TEXT NOT NULL,
    artist TEXT,
    played_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    listen_seconds INT DEFAULT 0,
    INDEX idx_user_played (user_id, played_at),
    FOREIGN KEY (user_id) REFERENCES ios_users(id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS ios_user_settings (
    user_id VARCHAR(36) PRIMARY KEY,
    audio_settings_json MEDIUMTEXT,
    theme_color VARCHAR(7) DEFAULT '#EC4079',
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    FOREIGN KEY (user_id) REFERENCES ios_users(id) ON DELETE CASCADE
);

-- Profile extensions: avatar and DOB (DOB immutable once set without admin)
ALTER TABLE ios_users ADD COLUMN IF NOT EXISTS date_of_birth DATE NULL;
ALTER TABLE ios_users ADD COLUMN IF NOT EXISTS avatar_data MEDIUMBLOB NULL;

-- Per-track audio settings overrides, stored as a JSON map of song id -> AudioSettings.
ALTER TABLE ios_user_settings ADD COLUMN IF NOT EXISTS track_audio_settings_json MEDIUMTEXT;

-- User library tracking: what songs the user has played/imported
CREATE TABLE IF NOT EXISTS ios_user_library (
    id VARCHAR(36) PRIMARY KEY,
    user_id VARCHAR(36) NOT NULL,
    song_id VARCHAR(255) NOT NULL,
    title TEXT NOT NULL,
    artist TEXT,
    album TEXT,
    source VARCHAR(20) DEFAULT 'local',  -- 'local', 'youtube', 'soundcloud', 'apple_music'
    play_count INT DEFAULT 0,
    skip_count INT DEFAULT 0,
    last_played TIMESTAMP NULL,
    added_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE KEY user_song (user_id, song_id),
    FOREIGN KEY (user_id) REFERENCES ios_users(id) ON DELETE CASCADE
);

-- Expanded settings (audio + visual preferences)
CREATE TABLE IF NOT EXISTS ios_user_settings_expanded (
    user_id VARCHAR(36) PRIMARY KEY,
    audio_settings_json MEDIUMTEXT,
    theme_color VARCHAR(7) DEFAULT '#EC4079',
    vinyl_disc_enabled BOOLEAN DEFAULT TRUE,
    show_queue_preview BOOLEAN DEFAULT TRUE,
    songs_per_row INT DEFAULT 1,
    albums_per_row INT DEFAULT 2,
    bg_animation VARCHAR(20) DEFAULT 'fade',
    bg_opacity FLOAT DEFAULT 0.35,
    preferred_audio_format VARCHAR(10) DEFAULT 'm4a',
    download_path TEXT,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    FOREIGN KEY (user_id) REFERENCES ios_users(id) ON DELETE CASCADE
);

-- Per-user music upload audit log (actual files live on disk in USER_MUSIC_DIR)
CREATE TABLE IF NOT EXISTS ios_user_music_uploads (
    id VARCHAR(36) PRIMARY KEY,
    user_id VARCHAR(36) NOT NULL,
    filename TEXT NOT NULL,
    folder VARCHAR(255) DEFAULT '',
    file_size_bytes INT DEFAULT 0,
    uploaded_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_user_uploads (user_id, uploaded_at),
    FOREIGN KEY (user_id) REFERENCES ios_users(id) ON DELETE CASCADE
);

-- Rich metadata for uploaded user music files (keyed by SHA-256 of file content)
CREATE TABLE IF NOT EXISTS ios_user_music_metadata (
  id VARCHAR(64) PRIMARY KEY,
  user_id VARCHAR(36) NOT NULL,
  filename VARCHAR(255) NOT NULL,
  original_filename VARCHAR(255),
  title VARCHAR(255),
  artist VARCHAR(255),
  album VARCHAR(255),
  genre VARCHAR(100),
  year VARCHAR(10),
  duration_seconds FLOAT,
  file_size_bytes BIGINT,
  bitrate INT,
  sample_rate INT,
  mime_type VARCHAR(50),
  has_artwork BOOLEAN DEFAULT FALSE,
  uploaded_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (user_id) REFERENCES ios_users(id) ON DELETE CASCADE,
  INDEX idx_user_id (user_id)
);

-- `filename` above is only ever the bare basename (see upload_user_music's
-- `safe_name`), but the actual on-disk location used by GET /user/music/stream
-- can include a subfolder (`folder` param at upload time) — the two only
-- coincide for root-level uploads. Any feature that needs to turn a
-- ios_user_music_metadata row back into a playable stream URL (e.g. the
-- weekly mix, 2026-07-19) needs the real relative path, not just the
-- filename. NULL for rows uploaded before this column existed; backfilled
-- automatically the next time that same file is (re-)uploaded.
ALTER TABLE ios_user_music_metadata ADD COLUMN IF NOT EXISTS relative_path VARCHAR(500) NULL;

-- Per-user gallery images (cloud-synced)
CREATE TABLE IF NOT EXISTS ios_user_gallery_images (
  id VARCHAR(36) PRIMARY KEY DEFAULT (UUID()),
  user_id VARCHAR(36) NOT NULL,
  filename VARCHAR(255) NOT NULL,
  display_order INT DEFAULT 0,
  uploaded_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (user_id) REFERENCES ios_users(id) ON DELETE CASCADE,
  INDEX idx_user_id (user_id)
);

-- iOS client telemetry / background log ingestion
CREATE TABLE IF NOT EXISTS ios_app_logs (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    level VARCHAR(10),
    category VARCHAR(30),
    message TEXT,
    file VARCHAR(100),
    line INT,
    timestamp TIMESTAMP NULL,
    extra JSON,
    device_model VARCHAR(50) NULL,
    os_version VARCHAR(20) NULL,
    app_version VARCHAR(20) NULL,
    user_id VARCHAR(36) NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_level (level),
    INDEX idx_created (created_at),
    INDEX idx_user (user_id)
);
ALTER TABLE ios_app_logs ADD COLUMN IF NOT EXISTS device_model VARCHAR(50) NULL;
ALTER TABLE ios_app_logs ADD COLUMN IF NOT EXISTS os_version VARCHAR(20) NULL;
ALTER TABLE ios_app_logs ADD COLUMN IF NOT EXISTS app_version VARCHAR(20) NULL;
ALTER TABLE ios_app_logs ADD COLUMN IF NOT EXISTS user_id VARCHAR(36) NULL;

-- Collaborative playlist sharing (snapshot-based, bridge side)
CREATE TABLE IF NOT EXISTS ios_shared_playlists (
  id VARCHAR(36) PRIMARY KEY DEFAULT (UUID()),
  playlist_id VARCHAR(36) NOT NULL,
  owner_user_id VARCHAR(36) NOT NULL,
  share_token VARCHAR(36) UNIQUE NOT NULL,
  playlist_data JSON NOT NULL DEFAULT ('{}'),
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  is_active BOOLEAN DEFAULT TRUE,
  FOREIGN KEY (owner_user_id) REFERENCES ios_users(id) ON DELETE CASCADE
);

-- In-app bug reports submitted from Settings → Help & Feature Guide → Report a Bug.
-- user_id is nullable since the app is usable without an account.
CREATE TABLE IF NOT EXISTS ios_bug_reports (
    id VARCHAR(36) PRIMARY KEY,
    user_id VARCHAR(36) NULL,
    category VARCHAR(30) DEFAULT 'other',
    description TEXT NOT NULL,
    contact_email VARCHAR(255),
    app_version VARCHAR(20),
    device_info VARCHAR(255),
    recent_logs MEDIUMTEXT,
    status VARCHAR(20) DEFAULT 'open',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_status (status),
    INDEX idx_created (created_at),
    FOREIGN KEY (user_id) REFERENCES ios_users(id) ON DELETE SET NULL
);

-- Opt-in flag for the public listening activity / discovery feature.
-- When TRUE, this user's recent plays (song title/artist only — never file
-- contents or URLs) are visible to other signed-in users via GET /social/*.
ALTER TABLE ios_users ADD COLUMN IF NOT EXISTS share_listening_activity BOOLEAN DEFAULT FALSE;

-- Opt-in flag for AI-assisted suggestions (see ios-bridge/intelligence.py).
-- When TRUE, this user's track titles/artists/genres may be sent to
-- Anthropic's API to improve metadata/EQ/duplicate/mix decisions that
-- otherwise fall back to the existing rule-based heuristics. Off by default —
-- this is the first feature in the app that sends track data to a
-- third-party API.
ALTER TABLE ios_users ADD COLUMN IF NOT EXISTS ai_assisted_suggestions BOOLEAN DEFAULT FALSE;

-- Per-user snapshots of sync data (favorites, playlists, settings), taken
-- automatically before any operation that overwrites that data server-side
-- (notably POST /user/sync, which replaces all favorites/playlists in one
-- shot). Lets a user recover if a bad push from a buggy/offline client wipes
-- their server-side library. Pruned to the most recent N per user.
CREATE TABLE IF NOT EXISTS ios_user_backups (
    id VARCHAR(36) PRIMARY KEY,
    user_id VARCHAR(36) NOT NULL,
    reason VARCHAR(30) NOT NULL,
    snapshot_json MEDIUMTEXT NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_user_created (user_id, created_at),
    FOREIGN KEY (user_id) REFERENCES ios_users(id) ON DELETE CASCADE
);

-- Per-user audit log of sync activity (push/pull/restore), for diagnosing
-- "where did my data go" reports without digging through ios_app_logs.
CREATE TABLE IF NOT EXISTS ios_sync_log (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    user_id VARCHAR(36) NOT NULL,
    action VARCHAR(20) NOT NULL,
    details VARCHAR(255),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_user_created (user_id, created_at),
    FOREIGN KEY (user_id) REFERENCES ios_users(id) ON DELETE CASCADE
);

-- Fix playlist_id column type in ios_shared_playlists (was INT, must be VARCHAR for UUID strings).
-- Must run after the CREATE TABLE above — on a fresh database this ALTER previously executed
-- before the table existed, causing init_db() to throw "table doesn't exist", roll back
-- (a no-op since DDL auto-commits in MySQL), and crash the bridge on startup before
-- ios_app_logs/ios_shared_playlists were ever created.
ALTER TABLE ios_shared_playlists MODIFY COLUMN playlist_id VARCHAR(36) NOT NULL DEFAULT '';

-- ---------------------------------------------------------------------------
-- 10 new server-side features
-- ---------------------------------------------------------------------------

-- Feature: cross-device "continue listening" — last playback position per user
CREATE TABLE IF NOT EXISTS ios_playback_state (
    user_id VARCHAR(36) PRIMARY KEY,
    song_id VARCHAR(255),
    title TEXT,
    artist TEXT,
    track_url TEXT,
    source VARCHAR(20),
    position_seconds FLOAT DEFAULT 0,
    duration_seconds FLOAT DEFAULT 0,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    FOREIGN KEY (user_id) REFERENCES ios_users(id) ON DELETE CASCADE
);

-- Feature: local Discord Rich Presence daemon needs to distinguish
-- playing vs. paused (a stale "now playing" row alone isn't enough).
ALTER TABLE ios_playback_state ADD COLUMN IF NOT EXISTS is_playing BOOLEAN DEFAULT TRUE;

-- Feature: surface the current track's BPM/tempo (from on-device analysis or
-- embedded tags) to other surfaces — widget "Continue Listening" and the local
-- Discord Rich Presence daemon, which can show it in the activity details line.
ALTER TABLE ios_playback_state ADD COLUMN IF NOT EXISTS bpm FLOAT NULL;

-- Feature: server-side loudness normalization (ReplayGain-style)
ALTER TABLE ios_user_music_metadata ADD COLUMN IF NOT EXISTS loudness_lufs FLOAT NULL;

-- Feature: scheduled playlist refresh — track a source URL per playlist so the
-- bridge can periodically re-resolve it and flag newly-added tracks.
ALTER TABLE ios_user_playlists ADD COLUMN IF NOT EXISTS source_url TEXT NULL;
ALTER TABLE ios_user_playlists ADD COLUMN IF NOT EXISTS source_checked_at TIMESTAMP NULL;
ALTER TABLE ios_user_playlists ADD COLUMN IF NOT EXISTS source_new_count INT DEFAULT 0;

-- Feature: shared listening rooms — host broadcasts current track/position,
-- guests poll for state.
CREATE TABLE IF NOT EXISTS ios_listen_rooms (
    id VARCHAR(36) PRIMARY KEY,
    host_user_id VARCHAR(36) NOT NULL,
    room_code VARCHAR(8) UNIQUE NOT NULL,
    track_url TEXT,
    title TEXT,
    artist TEXT,
    position_seconds FLOAT DEFAULT 0,
    is_playing BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    FOREIGN KEY (host_user_id) REFERENCES ios_users(id) ON DELETE CASCADE
);

-- ---------------------------------------------------------------------------
-- 10 more server-side features + Discord webhook integration
-- ---------------------------------------------------------------------------

-- Feature: artist/channel subscriptions — bridge periodically re-resolves
-- channel_url and compares against last_video_id to detect new uploads.
CREATE TABLE IF NOT EXISTS ios_artist_subscriptions (
    id VARCHAR(36) PRIMARY KEY,
    user_id VARCHAR(36) NOT NULL,
    channel_url TEXT NOT NULL,
    channel_name VARCHAR(255),
    last_video_id VARCHAR(64),
    last_checked_at TIMESTAMP NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_user (user_id),
    FOREIGN KEY (user_id) REFERENCES ios_users(id) ON DELETE CASCADE
);

-- Feature: collaborative playlists — additional users granted editor/viewer
-- access to a playlist they don't own.
CREATE TABLE IF NOT EXISTS ios_playlist_collaborators (
    playlist_id VARCHAR(36) NOT NULL,
    user_id VARCHAR(36) NOT NULL,
    role VARCHAR(10) NOT NULL DEFAULT 'editor',
    added_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (playlist_id, user_id),
    FOREIGN KEY (playlist_id) REFERENCES ios_user_playlists(id) ON DELETE CASCADE,
    FOREIGN KEY (user_id) REFERENCES ios_users(id) ON DELETE CASCADE
);

-- Feature: persistent server-side "up next" queue, independent of
-- ios_playback_state (which only tracks the current track/position).
CREATE TABLE IF NOT EXISTS ios_user_queue (
    id VARCHAR(36) PRIMARY KEY,
    user_id VARCHAR(36) NOT NULL,
    position INT NOT NULL DEFAULT 0,
    local_song_id VARCHAR(255),
    track_url TEXT,
    title TEXT NOT NULL,
    artist TEXT,
    album TEXT,
    duration_seconds INT DEFAULT 0,
    added_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_user_position (user_id, position),
    FOREIGN KEY (user_id) REFERENCES ios_users(id) ON DELETE CASCADE
);

-- Feature: scrobbling to Last.fm / ListenBrainz
CREATE TABLE IF NOT EXISTS ios_scrobble_links (
    user_id VARCHAR(36) PRIMARY KEY,
    lastfm_session_key VARCHAR(64) NULL,
    lastfm_username VARCHAR(255) NULL,
    listenbrainz_token VARCHAR(64) NULL,
    enabled BOOLEAN DEFAULT TRUE,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    FOREIGN KEY (user_id) REFERENCES ios_users(id) ON DELETE CASCADE
);

-- Feature: BPM analysis alongside the existing loudness pass
ALTER TABLE ios_user_music_metadata ADD COLUMN IF NOT EXISTS bpm FLOAT NULL;

-- Feature: search autocomplete / trending searches
CREATE TABLE IF NOT EXISTS ios_search_log (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    user_id VARCHAR(36) NULL,
    query VARCHAR(255) NOT NULL,
    source VARCHAR(20) DEFAULT 'youtube',
    searched_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_query (query),
    INDEX idx_searched (searched_at)
);

-- Feature: playlist folders/tags for organization
ALTER TABLE ios_user_playlists ADD COLUMN IF NOT EXISTS folder VARCHAR(255) NULL;
ALTER TABLE ios_user_playlists ADD COLUMN IF NOT EXISTS tags_json TEXT NULL;

-- Feature: push notifications — registered device tokens + an in-app
-- notification feed (room invites, subscription uploads, collaborator adds).
CREATE TABLE IF NOT EXISTS ios_push_tokens (
    user_id VARCHAR(36) NOT NULL,
    device_token VARCHAR(255) NOT NULL,
    platform VARCHAR(10) DEFAULT 'ios',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (user_id, device_token),
    FOREIGN KEY (user_id) REFERENCES ios_users(id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS ios_notifications (
    id VARCHAR(36) PRIMARY KEY,
    user_id VARCHAR(36) NOT NULL,
    type VARCHAR(30) NOT NULL,
    title VARCHAR(255) NOT NULL,
    body TEXT,
    data_json TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    read_at TIMESTAMP NULL,
    INDEX idx_user_created (user_id, created_at),
    FOREIGN KEY (user_id) REFERENCES ios_users(id) ON DELETE CASCADE
);

-- Per-user YouTube Data API v3 key, used by /api/resolve to enumerate full
-- YouTube playlists via playlistItems.list (bypassing yt-dlp's ~205-entry
-- flat-playlist cap). Falls back to the server-wide YOUTUBE_API_KEY env var
-- when a user hasn't set their own.
ALTER TABLE ios_user_settings ADD COLUMN IF NOT EXISTS youtube_api_key VARCHAR(128) NULL;

-- Per-user AcoustID API key (free registration at acoustid.org), used by
-- POST /api/fingerprint/identify to look up a Chromaprint fingerprint against
-- the AcoustID/MusicBrainz database for tracks with wrong or missing tags.
-- No server-wide fallback -- AcoustID client keys identify an application
-- registration, not a shared service credential, so each user brings their own.
ALTER TABLE ios_user_settings ADD COLUMN IF NOT EXISTS acoustid_api_key VARCHAR(128) NULL;

-- Per-user yt-dlp cookies (Netscape cookies.txt format), used to authenticate
-- yt-dlp extraction (search/stream/resolve/download) as that user's YouTube
-- session — required for age-restricted content and avoids YouTube's
-- anonymous-request bot-detection blocks. Never echoed back to clients (see
-- the /user/ytdlp-cookies status + /user/ytdlp-cookies/validate endpoints).
ALTER TABLE ios_user_settings ADD COLUMN IF NOT EXISTS ytdlp_cookies MEDIUMTEXT NULL;
ALTER TABLE ios_user_settings ADD COLUMN IF NOT EXISTS ytdlp_cookies_updated_at TIMESTAMP NULL;

-- Feature: Discord "now playing" webhook integration. True per-user Discord
-- Rich Presence ("Listening to ...") requires the Discord desktop client and
-- a local IPC connection, which an iOS app cannot establish on a user's
-- behalf — so instead each user can point a Discord webhook (e.g. at a
-- channel in their own server) and the bridge posts a "Now Playing" embed.
CREATE TABLE IF NOT EXISTS ios_discord_webhooks (
    user_id VARCHAR(36) PRIMARY KEY,
    webhook_url TEXT NOT NULL,
    enabled BOOLEAN DEFAULT TRUE,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    FOREIGN KEY (user_id) REFERENCES ios_users(id) ON DELETE CASCADE
);

-- Feature: Discord Rich Presence registration. Rich Presence itself is still
-- set by a local daemon talking to the Discord desktop client over IPC (no
-- server-side API exists for this), but the daemon's per-user configuration
-- (Discord Application client ID + optional Rich Presence art asset name) is
-- registered here once via the app, so the daemon only needs the per-user
-- RPC token (see /user/rpc-token) and fetches the rest from the server.
CREATE TABLE IF NOT EXISTS ios_discord_rpc_config (
    user_id VARCHAR(36) PRIMARY KEY,
    discord_client_id VARCHAR(64) NOT NULL,
    large_image VARCHAR(255),
    enabled BOOLEAN DEFAULT TRUE,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    FOREIGN KEY (user_id) REFERENCES ios_users(id) ON DELETE CASCADE
);

-- Feature: enhanced Discord Rich Presence — small "play/pause" status icon
-- asset and an optional "Listen on <source>" button linking to the track.
ALTER TABLE ios_discord_rpc_config ADD COLUMN IF NOT EXISTS small_image VARCHAR(255);
ALTER TABLE ios_discord_rpc_config ADD COLUMN IF NOT EXISTS show_buttons BOOLEAN DEFAULT TRUE;

-- Feature: musical key estimation (Krumhansl-Schmuckler chroma analysis)
-- alongside BPM/loudness, for harmonic-mixing-aware automixing/crossfade.
ALTER TABLE ios_user_music_metadata ADD COLUMN IF NOT EXISTS musical_key VARCHAR(16) NULL;

-- Feature: trending-by-energy — records each played track's BPM (from
-- on-device analysis or embedded tags) so /social/trending-by-energy can
-- rank trending tracks by average tempo, not just play count.
ALTER TABLE ios_play_history ADD COLUMN IF NOT EXISTS bpm FLOAT NULL;

-- Per-folder backup of the user's "watched folders" (MusicFolderService) tree
-- structure: which relative path under Documents each watched folder lived
-- at, and which tracks (by source track ID / title+artist+duration, since
-- on-device file paths aren't portable across installs) it contained. Pushed
-- alongside /user/sync so a reinstall can recreate the same folder layout and
-- prompt the user to redownload tracks back into their original folders.
-- Replaced wholesale on each push (one row per folder), like
-- ios_user_playlists/ios_playlist_tracks.
CREATE TABLE IF NOT EXISTS ios_user_folder_backups (
    id VARCHAR(36) PRIMARY KEY,
    user_id VARCHAR(36) NOT NULL,
    folder_path VARCHAR(1024) NOT NULL,
    track_filenames_json MEDIUMTEXT NOT NULL,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    INDEX idx_user_id (user_id),
    FOREIGN KEY (user_id) REFERENCES ios_users(id) ON DELETE CASCADE
);

-- Feature: Libre.fm scrobbling (Last.fm-API-compatible, different base URL).
-- Stored separately from the lastfm_* columns since a user may link both
-- independently.
ALTER TABLE ios_scrobble_links ADD COLUMN IF NOT EXISTS librefm_session_key VARCHAR(64) NULL;

-- Expanded per-user sync settings: visual/layout preferences that previously
-- lived only in ios_user_settings_expanded (unused by /user/sync) are now
-- also mirrored onto ios_user_settings so they round-trip through the normal
-- 8-minute auto-sync / manual sync (GET+POST /user/sync).
ALTER TABLE ios_user_settings ADD COLUMN IF NOT EXISTS vinyl_disc_enabled BOOLEAN DEFAULT TRUE;
ALTER TABLE ios_user_settings ADD COLUMN IF NOT EXISTS show_queue_preview BOOLEAN DEFAULT TRUE;
ALTER TABLE ios_user_settings ADD COLUMN IF NOT EXISTS songs_per_row INT DEFAULT 1;
ALTER TABLE ios_user_settings ADD COLUMN IF NOT EXISTS albums_per_row INT DEFAULT 2;
ALTER TABLE ios_user_settings ADD COLUMN IF NOT EXISTS bg_animation VARCHAR(20) DEFAULT 'fade';
ALTER TABLE ios_user_settings ADD COLUMN IF NOT EXISTS bg_opacity FLOAT DEFAULT 0.35;
ALTER TABLE ios_user_settings ADD COLUMN IF NOT EXISTS preferred_audio_format VARCHAR(10) DEFAULT 'm4a';
ALTER TABLE ios_user_settings ADD COLUMN IF NOT EXISTS download_path TEXT NULL;

-- New sync fields (Feature: expanded sync payload).
ALTER TABLE ios_user_settings ADD COLUMN IF NOT EXISTS car_mode_enabled BOOLEAN DEFAULT FALSE;
ALTER TABLE ios_user_settings ADD COLUMN IF NOT EXISTS library_artists_columns INT DEFAULT 2;
ALTER TABLE ios_user_settings ADD COLUMN IF NOT EXISTS now_playing_artwork_style VARCHAR(32) NULL;
ALTER TABLE ios_user_settings ADD COLUMN IF NOT EXISTS now_playing_seeker_style VARCHAR(32) NULL;
-- now_playing_artwork_style holds EITHER a built-in style's short rawValue OR
-- a user-created CustomNowPlayingStyle's UUID id (NowPlayingView.swift's
-- selectStyle) — a UUID string is 36 chars, which doesn't fit VARCHAR(32) and
-- 500s the whole settings sync for anyone using a custom style. Widen to
-- match channel_id's VARCHAR(64) below. Plain MODIFY is idempotent (a no-op
-- once already widened), unlike ADD COLUMN IF NOT EXISTS.
ALTER TABLE ios_user_settings MODIFY COLUMN now_playing_artwork_style VARCHAR(64) NULL;
ALTER TABLE ios_user_settings ADD COLUMN IF NOT EXISTS earned_badges_json MEDIUMTEXT NULL;
-- Generic JSON bag of additional UserDefaults-backed preferences included in
-- the per-user auto backup (notifications toggle, card style, auto-radio,
-- Liquid Glass customization, etc.). A single extensible column so new
-- settings can be backed up without per-field schema migrations.
ALTER TABLE ios_user_settings ADD COLUMN IF NOT EXISTS extra_settings_json MEDIUMTEXT NULL;

-- The client (AccountService+Sync.swift) has built and sent bg_enabled/
-- bg_blur_radius/bg_shuffle_interval in every sync push since the gallery
-- background feature shipped, but no column ever existed for them here —
-- Pydantic's SyncPushRequest silently dropped the extra JSON keys, so a
-- fresh install never restored whether the gallery background was on, its
-- blur radius, or its shuffle interval. Filling that gap now.
ALTER TABLE ios_user_settings ADD COLUMN IF NOT EXISTS bg_enabled BOOLEAN DEFAULT TRUE;
ALTER TABLE ios_user_settings ADD COLUMN IF NOT EXISTS bg_blur_radius FLOAT NULL;
ALTER TABLE ios_user_settings ADD COLUMN IF NOT EXISTS bg_shuffle_interval FLOAT NULL;

-- Previously device-local-only stores, now included in the per-user auto
-- backup — see SyncData's Swift-side doc comments (AccountModels.swift) for
-- why each of these was a real gap (Smart Playlists, tracked/auto-download
-- playlists, play history/stats, track bookmarks, and per-track BPM keyed
-- portably by sourceTrackID rather than the on-device-only path/mtime/size
-- key BPMAnalyzerService's own cache uses).
ALTER TABLE ios_user_settings ADD COLUMN IF NOT EXISTS play_history_json MEDIUMTEXT NULL;
ALTER TABLE ios_user_settings ADD COLUMN IF NOT EXISTS smart_playlists_json MEDIUMTEXT NULL;
ALTER TABLE ios_user_settings ADD COLUMN IF NOT EXISTS tracked_playlists_json MEDIUMTEXT NULL;
ALTER TABLE ios_user_settings ADD COLUMN IF NOT EXISTS bookmarks_json MEDIUMTEXT NULL;
ALTER TABLE ios_user_settings ADD COLUMN IF NOT EXISTS bpm_by_source_track_id_json MEDIUMTEXT NULL;

-- Feature: Discover subscriptions — resolve a user-entered channel
-- URL/handle/search term to a real YouTube channel_id + thumbnail at
-- subscribe time, so the subscription list can show real channel art
-- instead of just the raw URL the user typed.
ALTER TABLE ios_artist_subscriptions ADD COLUMN IF NOT EXISTS channel_id VARCHAR(64) NULL;
ALTER TABLE ios_artist_subscriptions ADD COLUMN IF NOT EXISTS channel_thumbnail TEXT NULL;
ALTER TABLE ios_scrobble_links ADD COLUMN IF NOT EXISTS librefm_username VARCHAR(255) NULL;

-- Records every track a user has successfully downloaded via /api/download
-- (regardless of whether they later delete/lose the local file). Powers:
--   - "My Library" search (find tracks the user has ever had, even if the
--     on-device library doesn't currently have them)
--   - "Previously downloaded" restore list after reinstall/corruption-delete
--   - Listening/download stats (most-downloaded artists, totals, etc.)
CREATE TABLE IF NOT EXISTS ios_download_history (
    id VARCHAR(36) PRIMARY KEY,
    user_id VARCHAR(36) NOT NULL,
    source VARCHAR(20) NOT NULL,
    source_id VARCHAR(255) NOT NULL,
    title TEXT NOT NULL,
    artist TEXT,
    thumbnail_url TEXT,
    duration_seconds INT DEFAULT 0,
    format VARCHAR(10) DEFAULT 'm4a',
    download_count INT DEFAULT 1,
    first_downloaded_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    last_downloaded_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    UNIQUE KEY user_track (user_id, source, source_id),
    INDEX idx_user_history (user_id, last_downloaded_at),
    FOREIGN KEY (user_id) REFERENCES ios_users(id) ON DELETE CASCADE
);

-- Durable record of a finished /api/download job whose file hasn't been
-- fetched by the client yet. Previously a finished job's file lived only in
-- an ephemeral temp dir and was deleted 15 minutes after creation regardless
-- of whether the client had fetched it — if the app was closed/backgrounded
-- while a job was still running (or briefly after), the finished download
-- was silently lost with no way to recover it. Rows here persist (bounded by
-- a long-term sweep, see _sweep_stale_pending_downloads) until the client
-- fetches the file via /api/download/result, so a job started from any
-- session/device state can always be picked up later by
-- GET /api/download/pending — on next app launch, next foreground, the next
-- BGAppRefreshTask run, or immediately via a silent push (see
-- _send_push_best_effort's content_available parameter).
CREATE TABLE IF NOT EXISTS ios_pending_downloads (
    job_id VARCHAR(36) PRIMARY KEY,
    user_id VARCHAR(36) NOT NULL,
    source_track_id VARCHAR(280) NOT NULL,
    title TEXT,
    artist TEXT,
    file_path TEXT NOT NULL,
    media_type VARCHAR(50) NOT NULL,
    filename TEXT NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_pending_user (user_id, created_at),
    FOREIGN KEY (user_id) REFERENCES ios_users(id) ON DELETE CASCADE
);

-- Per-user snapshot of the source ids CURRENTLY in the user's on-device library
-- (Song.sourceTrackID values + download-ledger ids), uploaded periodically by
-- the app. yt-dlp/the bridge can never see the device's folders, so this is how
-- the server knows what the user already has: the resolve + single-download
-- dedup consult it so re-downloading a playlist skips owned tracks even when the
-- per-request existing_ids manifest is incomplete or too large for a URL. Unlike
-- ios_download_history (append-only "ever downloaded"), this is replaced on each
-- sync, so deleting a track on-device lets it be downloaded again.
CREATE TABLE IF NOT EXISTS ios_user_library_inventory (
    user_id VARCHAR(36) NOT NULL,
    source_id VARCHAR(255) NOT NULL,
    PRIMARY KEY (user_id, source_id),
    FOREIGN KEY (user_id) REFERENCES ios_users(id) ON DELETE CASCADE
);

-- ---------------------------------------------------------------------------
-- 10 more server-side features (2026-07-04)
-- ---------------------------------------------------------------------------

-- Feature: full-text search over the user's own uploaded music library.
-- /user/music's `search` param scans the whole filesystem + runs ffprobe on
-- every file on every request — slow for big libraries and no typo
-- tolerance. This FULLTEXT index lets /user/music/search query the
-- already-populated metadata table directly instead.
ALTER TABLE ios_user_music_metadata ADD FULLTEXT INDEX IF NOT EXISTS ft_search (title, artist, album);

-- Feature: per-user storage quota override. NULL/0 means "use the server
-- default" (USER_MUSIC_QUOTA_BYTES env var, itself unlimited unless the
-- admin sets it) — this column exists only so a specific user's quota can
-- be raised/lowered without changing the server-wide default.
ALTER TABLE ios_user_settings ADD COLUMN IF NOT EXISTS storage_quota_bytes BIGINT NULL;

-- Feature: server-side lyrics cache. /api/lyrics previously re-fetched from
-- lrclib.net on every single request, even for the same song looked up
-- repeatedly (every time Now Playing opens). Cached indefinitely since
-- lyrics for a given track essentially never change; a user-submitted
-- correction (is_user_submitted) overwrites the lrclib result and is never
-- evicted by a later automatic re-fetch.
CREATE TABLE IF NOT EXISTS ios_lyrics_cache (
    id VARCHAR(64) PRIMARY KEY,
    title VARCHAR(255) NOT NULL,
    artist VARCHAR(255) NOT NULL,
    synced_lyrics MEDIUMTEXT NULL,
    plain_lyrics MEDIUMTEXT NULL,
    found BOOLEAN NOT NULL DEFAULT FALSE,
    is_user_submitted BOOLEAN NOT NULL DEFAULT FALSE,
    submitted_by_user_id VARCHAR(36) NULL,
    cached_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    INDEX idx_title_artist (title, artist)
);

-- Cache of GET /api/artist/bio results (MusicBrainz facts + Wikipedia bio
-- text/photo — see main.py). artist_name is the lowercased/trimmed lookup
-- key. `found = FALSE` rows are real cache entries too (a typo'd/obscure
-- name that matched nothing), so a bad lookup isn't re-queried against
-- MusicBrainz/Wikipedia on every visit to that artist's page. Refreshed on
-- a 30-day TTL (checked in the endpoint itself via `cached_at`), not
-- indefinitely — unlike lyrics, a bio can meaningfully change over time.
CREATE TABLE IF NOT EXISTS ios_artist_bio_cache (
    artist_name VARCHAR(255) PRIMARY KEY,
    bio_json MEDIUMTEXT NULL,
    found BOOLEAN NOT NULL DEFAULT FALSE,
    cached_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
);

-- Cache of Claude "intelligence" task results (see ios-bridge/intelligence.py),
-- keyed by task + a hash of the normalized input. Results here are stable
-- decisions (e.g. "which metadata candidate is correct for this filename"),
-- so they're cached indefinitely rather than on a TTL.
CREATE TABLE IF NOT EXISTS ios_intelligence_cache (
    task VARCHAR(32) NOT NULL,
    cache_key VARCHAR(64) NOT NULL,
    result_json MEDIUMTEXT NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (task, cache_key)
);

-- Aria Lumi's memory (see ios-bridge/intelligence.py): one row per suggestion
-- she makes, updated with correction_json whenever the user's actual choice
-- differs from her pick. Recent corrections (correction_json IS NOT NULL) are
-- fed back into her next prompt for that task as few-shot examples, so her
-- judgment concretely improves from real usage instead of resetting on every
-- request. Kept separate from ios_intelligence_cache (which caches a stable
-- decision for reuse) since this table's purpose is a learning signal, not
-- a cache — it's read in small recent-N slices, never looked up by key.
CREATE TABLE IF NOT EXISTS ios_aria_memory (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    user_id VARCHAR(36) NOT NULL,
    task VARCHAR(32) NOT NULL,
    input_json MEDIUMTEXT NOT NULL,
    ai_result_json MEDIUMTEXT NOT NULL,
    correction_json MEDIUMTEXT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_task_created (task, created_at)
);

-- Feature: server-side waveform peak-data precomputation, alongside the
-- existing loudness/BPM/key analysis at upload time — saves the client from
-- decoding the whole file locally just to draw a scrubber waveform. Stored
-- as a JSON array of ~200 normalized (0.0-1.0) peak values.
ALTER TABLE ios_user_music_metadata ADD COLUMN IF NOT EXISTS waveform_json MEDIUMTEXT NULL;

-- Feature: cached acoustic-duplicate scan results, computed by a periodic
-- background job (see _duplicate_scan_loop) instead of live on every
-- GET /user/library/acoustic-duplicates request, which was slow for large
-- libraries (re-fingerprinting everything on demand).
CREATE TABLE IF NOT EXISTS ios_duplicate_scan_cache (
    user_id VARCHAR(36) PRIMARY KEY,
    groups_json MEDIUMTEXT NOT NULL,
    scanned_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    FOREIGN KEY (user_id) REFERENCES ios_users(id) ON DELETE CASCADE
);

-- Feature: generalized outbound webhooks (beyond the existing Discord-only
-- ios_discord_webhooks). One row per (user, event type) so a user can point
-- different events at different URLs — e.g. downloads to one Zapier hook,
-- subscription-alerts to a Home Assistant endpoint.
CREATE TABLE IF NOT EXISTS ios_user_webhooks (
    id VARCHAR(36) PRIMARY KEY,
    user_id VARCHAR(36) NOT NULL,
    event_type VARCHAR(40) NOT NULL,
    webhook_url TEXT NOT NULL,
    enabled BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_user_event (user_id, event_type),
    FOREIGN KEY (user_id) REFERENCES ios_users(id) ON DELETE CASCADE
);

-- Feature: persistent listening-room chat/history — ios_listen_rooms only
-- tracks the host's current track/position; this records track changes and
-- chat messages so guests joining late (or reopening the room) see history.
CREATE TABLE IF NOT EXISTS ios_room_events (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    room_id VARCHAR(36) NOT NULL,
    user_id VARCHAR(36) NULL,
    event_type VARCHAR(20) NOT NULL,
    title TEXT NULL,
    artist TEXT NULL,
    message TEXT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_room_created (room_id, created_at),
    FOREIGN KEY (room_id) REFERENCES ios_listen_rooms(id) ON DELETE CASCADE,
    FOREIGN KEY (user_id) REFERENCES ios_users(id) ON DELETE SET NULL
);

-- Feature: collaborative room queue — members can add/vote on tracks for a
-- shared listening room's "up next" order, independent of the host's own
-- device queue.
CREATE TABLE IF NOT EXISTS ios_room_queue (
    id VARCHAR(36) PRIMARY KEY,
    room_id VARCHAR(36) NOT NULL,
    added_by_user_id VARCHAR(36) NULL,
    track_url TEXT,
    title TEXT NOT NULL,
    artist TEXT,
    votes INT DEFAULT 0,
    added_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_room_votes (room_id, votes),
    FOREIGN KEY (room_id) REFERENCES ios_listen_rooms(id) ON DELETE CASCADE,
    FOREIGN KEY (added_by_user_id) REFERENCES ios_users(id) ON DELETE SET NULL
);

-- Feature: personalized history-based weekly mix (distinct from the existing
-- static tempo-bucket ios_user_music_metadata-derived smart-playlists) —
-- caches the generated track-id list per user, regenerated weekly by
-- _weekly_mix_loop rather than computed per-request.
CREATE TABLE IF NOT EXISTS ios_weekly_mix_cache (
    user_id VARCHAR(36) PRIMARY KEY,
    track_ids_json MEDIUMTEXT NOT NULL,
    generated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    FOREIGN KEY (user_id) REFERENCES ios_users(id) ON DELETE CASCADE
);

-- ---------------------------------------------------------------------------
-- 3 more server-side features (2026-07-11)
-- ---------------------------------------------------------------------------

-- Feature: search my library by lyrics (see /api/lyrics/search,
-- /user/lyrics/prefetch in main.py). MATCH()'s column list must exactly match
-- a FULLTEXT index's columns, hence (title, artist, plain_lyrics) here rather
-- than plain_lyrics alone — lets a query also hit on title/artist words.
ALTER TABLE ios_lyrics_cache ADD FULLTEXT INDEX IF NOT EXISTS ft_lyrics_search (title, artist, plain_lyrics);

-- Feature: TOTP two-factor authentication (see /auth/2fa/* in main.py).
-- totp_secret is only meaningful once totp_enabled is TRUE (set by
-- /auth/2fa/verify after the user proves they scanned the QR code correctly —
-- /auth/2fa/setup alone does not turn 2FA on, so a half-finished setup can't
-- lock anyone out).
ALTER TABLE ios_users ADD COLUMN IF NOT EXISTS totp_secret VARCHAR(64) NULL;
ALTER TABLE ios_users ADD COLUMN IF NOT EXISTS totp_enabled BOOLEAN NOT NULL DEFAULT FALSE;

-- Feature: /social/similar-listeners collaborative-filtering recommendations.
-- No new tables — reuses ios_play_history and the existing
-- share_listening_activity opt-in (see the /social/* section in main.py).

-- ---------------------------------------------------------------------------
-- General-purpose DB event logging sweep
-- ---------------------------------------------------------------------------

-- Structured cross-system event log (auth, sync, backup, metadata/
-- intelligence, etc.) — see db.log_event() and POST /api/log-event in
-- main.py. Distinct from ios_app_logs (raw client debug-log-line ingestion
-- from AppLogger's local buffer) and the narrower ios_sync_log/
-- ios_search_log tables: this one is a single reusable sink for "something
-- happened" events from both the bridge itself (source='bridge') and the
-- iOS client (source='ios_client'), with an optional structured JSON detail
-- blob. user_id is nullable since some events (e.g. a failed login attempt
-- for an unknown username) have no known user yet.
CREATE TABLE IF NOT EXISTS ios_app_event_log (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    source VARCHAR(20) NOT NULL DEFAULT 'bridge',
    user_id VARCHAR(36) NULL,
    category VARCHAR(30) NOT NULL,
    event VARCHAR(60) NOT NULL,
    level VARCHAR(10) NOT NULL DEFAULT 'info',
    message TEXT,
    detail JSON NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_category_created (category, created_at),
    INDEX idx_user_created (user_id, created_at),
    INDEX idx_level (level)
);

-- ---------------------------------------------------------------------------
-- Download/streaming attempt logging (2026-07-18)
-- ---------------------------------------------------------------------------

-- Append-only log of every /api/download job attempt (start-to-finish, not
-- per internal yt-dlp retry) — start, success, or failure with a reason —
-- keyed loosely by (source, source_id) rather than a unique constraint since
-- the same track can be legitimately re-downloaded/re-attempted many times.
-- Distinct from ios_download_history (which only upserts successful,
-- account-linked downloads for "My Library"/stats): this is a plain diagnostic
-- trail that also covers anonymous downloads (user_id NULL) and failures, so
-- "why did my download fail" can be answered without grepping raw app logs.
-- user_id uses ON DELETE SET NULL (not CASCADE, unlike most other per-user
-- tables here) so a deleted account's download history stays available for
-- aggregate/ops diagnostics instead of disappearing with the account.
CREATE TABLE IF NOT EXISTS ios_download_log (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    user_id VARCHAR(36) NULL,
    source VARCHAR(20) NOT NULL,
    source_id VARCHAR(280) NOT NULL,
    title TEXT NULL,
    status VARCHAR(20) NOT NULL,
    error_message TEXT NULL,
    duration_ms INT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    completed_at TIMESTAMP NULL,
    INDEX idx_user_created (user_id, created_at),
    INDEX idx_source_id (source, source_id),
    FOREIGN KEY (user_id) REFERENCES ios_users(id) ON DELETE SET NULL
);

-- Streaming-side counterpart to ios_download_log: one row per
-- streaming-URL-resolution attempt (/api/stream, /api/stream/proxy) — a
-- track being played, not downloaded, so "status"/"error_message" describe
-- whether yt-dlp/the extractor produced a playable URL, not a downloaded file.
CREATE TABLE IF NOT EXISTS ios_stream_log (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    user_id VARCHAR(36) NULL,
    source VARCHAR(20) NOT NULL,
    source_id VARCHAR(280) NOT NULL,
    title TEXT NULL,
    status VARCHAR(20) NOT NULL,
    error_message TEXT NULL,
    duration_ms INT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    completed_at TIMESTAMP NULL,
    INDEX idx_user_created (user_id, created_at),
    INDEX idx_source_id (source, source_id),
    FOREIGN KEY (user_id) REFERENCES ios_users(id) ON DELETE SET NULL
);

-- ---------------------------------------------------------------------------
-- Social Ecosystem: profiles, friends, presence (2026-07-18)
--
-- Everything below is additive and namespaced ios_social_ / ios_presence_ so
-- it can never collide with another workstream's tables. All new endpoints
-- live under the /api/social/* prefix in main.py (deliberately distinct from
-- the pre-existing global, non-friend-scoped /social/* activity/discover
-- feed above, which is a different feature this doesn't replace).
-- ---------------------------------------------------------------------------

-- One row per user with a customized profile (created lazily on first save —
-- a user who never visits their profile screen simply has no row here, and
-- GET /api/social/profile/{id} falls back to defaults). main_accent_hex /
-- sub_accent_hex are validated server-side against a curated palette (see
-- AccentColorPickerView.swift) rather than accepting arbitrary hex strings
-- from the client, so a malformed value can never make a profile unreadable.
-- share_now_playing is the privacy hook requested for presence: when FALSE,
-- this user's now_playing_* fields are withheld from both the presence
-- endpoints and the friend activity feed (online/offline still shows).
CREATE TABLE IF NOT EXISTS ios_social_profiles (
    user_id VARCHAR(36) PRIMARY KEY,
    bio VARCHAR(280) NULL,
    main_accent_hex VARCHAR(7) NULL,
    sub_accent_hex VARCHAR(7) NULL,
    share_now_playing BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    FOREIGN KEY (user_id) REFERENCES ios_users(id) ON DELETE CASCADE
);

-- Profile banner image (2026-07-19) — same JPEG/GIF-sniffed-bytes pattern
-- as ios_users.avatar_data (see POST/GET /user/avatar), just scoped to the
-- social profile instead of the core account. NULL means "no banner set";
-- the profile header falls back to a plain main/sub accent gradient.
ALTER TABLE ios_social_profiles ADD COLUMN IF NOT EXISTS banner_data MEDIUMBLOB NULL;

-- Up to 5 user-pinned "favorite songs" shown on the profile, ordered by
-- `position` (0-4). Saved as a full replace (delete-then-insert in one
-- transaction) from PUT /api/social/profile/pinned-tracks rather than
-- incremental add/remove endpoints — simplest correct way to let the user
-- freely reorder/swap a small fixed-size list. Denormalized title/artist/
-- album (like ios_user_favorites and ios_playlist_tracks already do) so a
-- pin still displays something sensible even if source_track_id is null
-- (a purely local import) or the source later disappears.
CREATE TABLE IF NOT EXISTS ios_social_pinned_tracks (
    id VARCHAR(36) PRIMARY KEY,
    user_id VARCHAR(36) NOT NULL,
    position INT NOT NULL DEFAULT 0,
    source_track_id VARCHAR(255) NULL,
    track_url TEXT NULL,
    title TEXT NOT NULL,
    artist TEXT NULL,
    album TEXT NULL,
    added_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_pinned_user (user_id),
    FOREIGN KEY (user_id) REFERENCES ios_users(id) ON DELETE CASCADE
);

-- Friend requests. `status` moves pending -> accepted/declined/cancelled and
-- is never deleted (keeps a simple audit trail / prevents immediate re-spam
-- after a decline within the app's own request-throttling logic). Accepting
-- a request writes the symmetric pair into ios_social_friends below rather
-- than this table being queried for "are we friends" at read time.
CREATE TABLE IF NOT EXISTS ios_social_friend_requests (
    id VARCHAR(36) PRIMARY KEY,
    from_user_id VARCHAR(36) NOT NULL,
    to_user_id VARCHAR(36) NOT NULL,
    status VARCHAR(16) NOT NULL DEFAULT 'pending',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    responded_at TIMESTAMP NULL,
    INDEX idx_freq_to (to_user_id, status),
    INDEX idx_freq_from (from_user_id, status),
    FOREIGN KEY (from_user_id) REFERENCES ios_users(id) ON DELETE CASCADE,
    FOREIGN KEY (to_user_id) REFERENCES ios_users(id) ON DELETE CASCADE
);

-- Friendships, stored as a symmetric pair of rows (A,B) + (B,A) on accept —
-- a small denormalization that keeps every "who are my friends" /
-- "am I friends with X" query a single indexed lookup on `user_id` alone,
-- instead of an OR'd two-column match on every read. Both rows are deleted
-- together on unfriend or on either side blocking the other.
CREATE TABLE IF NOT EXISTS ios_social_friends (
    user_id VARCHAR(36) NOT NULL,
    friend_id VARCHAR(36) NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (user_id, friend_id),
    INDEX idx_friends_friend (friend_id),
    FOREIGN KEY (user_id) REFERENCES ios_users(id) ON DELETE CASCADE,
    FOREIGN KEY (friend_id) REFERENCES ios_users(id) ON DELETE CASCADE
);

-- Basic abuse handling for the friends feature: a block is one-directional
-- (user_id blocked blocked_id) but enforced both ways at query time (neither
-- side can friend-request, view the other's profile, or see them in
-- presence/activity once either has blocked the other). Blocking also tears
-- down any existing friendship/pending request between the two (see
-- POST /api/social/block/{user_id}).
CREATE TABLE IF NOT EXISTS ios_social_blocks (
    user_id VARCHAR(36) NOT NULL,
    blocked_id VARCHAR(36) NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (user_id, blocked_id),
    FOREIGN KEY (user_id) REFERENCES ios_users(id) ON DELETE CASCADE,
    FOREIGN KEY (blocked_id) REFERENCES ios_users(id) ON DELETE CASCADE
);

-- One row per user, upserted on every POST /api/social/presence heartbeat
-- (client polls every 30-60s while foregrounded — see PresenceService.swift).
-- "Online" is derived, not stored as a trusted-forever flag: callers should
-- treat a user as online only when is_online = TRUE *and* last_seen_at is
-- recent (main.py uses a 90s freshness window — 1.5x the client's slowest
-- polling cadence — so a force-quit/crashed app without the best-effort
-- "going offline" beacon still reads as offline shortly after, not forever
-- online). now_playing_title/artist are always stored as reported (same
-- "store raw, gate on read" convention the pre-existing global
-- share_listening_activity feed above already uses for ios_play_history) —
-- every /api/social/presence/* read filters them out whenever the owning
-- profile has share_now_playing = FALSE, so they are never returned by the
-- API to anyone while the toggle is off, and toggling it doesn't require
-- rewriting this row.
CREATE TABLE IF NOT EXISTS ios_presence_state (
    user_id VARCHAR(36) PRIMARY KEY,
    is_online BOOLEAN NOT NULL DEFAULT FALSE,
    is_playing BOOLEAN NOT NULL DEFAULT FALSE,
    now_playing_title VARCHAR(500) NULL,
    now_playing_artist VARCHAR(500) NULL,
    last_seen_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    FOREIGN KEY (user_id) REFERENCES ios_users(id) ON DELETE CASCADE
);

-- Feature: pending-download folder routing (2026-07-19). The job that
-- created a pending download already knows which local folder it's destined
-- for (e.g. a tracked playlist's own destination folder — see
-- TrackedPlaylist.destinationFolder client-side), but ios_pending_downloads
-- had nowhere to remember that once the job outlived the request that
-- started it. Without this, recovering a download after the app was closed
-- always fell back to the default folder, silently ignoring the playlist's
-- chosen destination. NULL means "use the default download folder", same
-- convention TrackedPlaylist.destinationFolder itself already uses.
ALTER TABLE ios_pending_downloads ADD COLUMN IF NOT EXISTS destination_folder VARCHAR(255) NULL;
