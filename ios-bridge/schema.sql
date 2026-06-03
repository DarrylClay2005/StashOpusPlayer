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
)
