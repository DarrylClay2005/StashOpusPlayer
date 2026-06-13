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
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_level (level),
    INDEX idx_created (created_at)
);

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
