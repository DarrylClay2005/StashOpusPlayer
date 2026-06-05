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
)
