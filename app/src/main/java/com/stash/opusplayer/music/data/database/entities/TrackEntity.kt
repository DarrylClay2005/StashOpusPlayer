package com.stash.opusplayer.music.data.database.entities

import androidx.room.ColumnInfo
import androidx.room.Entity
import androidx.room.Index
import androidx.room.PrimaryKey

/**
 * Track Entity - Complete track information
 * 
 * Represents a single audio track with comprehensive metadata,
 * audio analysis, and playback statistics
 */
@Entity(
    tableName = "tracks",
    indices = [
        Index(value = ["title"]),
        Index(value = ["artist"]),
        Index(value = ["album"]),
        Index(value = ["genre"]),
        Index(value = ["path"], unique = true),
        Index(value = ["artist", "album"]),
        Index(value = ["album_id"]),
        Index(value = ["artist_id"]),
        Index(value = ["is_favorite"]),
        Index(value = ["last_played"]),
        Index(value = ["play_count"]),
        Index(value = ["rating"])
    ]
)
data class TrackEntity(
    @PrimaryKey(autoGenerate = true)
    @ColumnInfo(name = "id")
    val id: Long = 0,
    
    // Basic metadata
    @ColumnInfo(name = "title")
    val title: String,
    
    @ColumnInfo(name = "artist")
    val artist: String,
    
    @ColumnInfo(name = "album")
    val album: String,
    
    @ColumnInfo(name = "album_artist")
    val albumArtist: String? = null,
    
    @ColumnInfo(name = "composer")
    val composer: String? = null,
    
    @ColumnInfo(name = "genre")
    val genre: String? = null,
    
    @ColumnInfo(name = "year")
    val year: Int? = null,
    
    @ColumnInfo(name = "track_number")
    val trackNumber: Int? = null,
    
    @ColumnInfo(name = "disc_number")
    val discNumber: Int? = null,
    
    // File information
    @ColumnInfo(name = "path")
    val path: String,
    
    @ColumnInfo(name = "uri")
    val uri: String,
    
    @ColumnInfo(name = "file_size")
    val fileSize: Long,
    
    @ColumnInfo(name = "mime_type")
    val mimeType: String,
    
    @ColumnInfo(name = "codec")
    val codec: String? = null,
    
    @ColumnInfo(name = "bitrate")
    val bitrate: Int? = null,
    
    @ColumnInfo(name = "sample_rate")
    val sampleRate: Int? = null,
    
    @ColumnInfo(name = "channels")
    val channels: Int? = null,
    
    @ColumnInfo(name = "bit_depth")
    val bitDepth: Int? = null,
    
    // Duration and timing
    @ColumnInfo(name = "duration")
    val duration: Long, // in milliseconds
    
    @ColumnInfo(name = "date_added")
    val dateAdded: Long,
    
    @ColumnInfo(name = "date_modified")
    val dateModified: Long,
    
    @ColumnInfo(name = "last_played")
    val lastPlayed: Long? = null,
    
    // Album art
    @ColumnInfo(name = "album_art_uri")
    val albumArtUri: String? = null,
    
    @ColumnInfo(name = "has_embedded_art")
    val hasEmbeddedArt: Boolean = false,
    
    // User data
    @ColumnInfo(name = "play_count")
    val playCount: Int = 0,
    
    @ColumnInfo(name = "skip_count")
    val skipCount: Int = 0,
    
    @ColumnInfo(name = "is_favorite")
    val isFavorite: Boolean = false,
    
    @ColumnInfo(name = "rating")
    val rating: Float = 0f, // 0-5 stars
    
    @ColumnInfo(name = "last_position")
    val lastPosition: Long = 0, // Resume position in ms
    
    // Quality metrics
    @ColumnInfo(name = "quality")
    val quality: String? = null, // LOSSY, LOSSLESS, HI_RES
    
    @ColumnInfo(name = "dynamic_range")
    val dynamicRange: Float? = null,
    
    @ColumnInfo(name = "loudness")
    val loudness: Float? = null, // LUFS
    
    @ColumnInfo(name = "replay_gain_track")
    val replayGainTrack: Float? = null,
    
    @ColumnInfo(name = "replay_gain_album")
    val replayGainAlbum: Float? = null,
    
    // AI/Advanced metadata
    @ColumnInfo(name = "ai_genre")
    val aiGenre: String? = null,
    
    @ColumnInfo(name = "ai_mood")
    val aiMood: String? = null,
    
    @ColumnInfo(name = "ai_energy")
    val aiEnergy: Float? = null, // 0-1
    
    @ColumnInfo(name = "ai_tempo")
    val aiTempo: Float? = null, // BPM
    
    @ColumnInfo(name = "ai_key")
    val aiKey: String? = null,
    
    @ColumnInfo(name = "ai_tags")
    val aiTags: String? = null, // JSON array
    
    // Lyrics and comments
    @ColumnInfo(name = "has_lyrics")
    val hasLyrics: Boolean = false,
    
    @ColumnInfo(name = "lyrics")
    val lyrics: String? = null,
    
    @ColumnInfo(name = "comment")
    val comment: String? = null,
    
    // Foreign keys
    @ColumnInfo(name = "album_id")
    val albumId: Long? = null,
    
    @ColumnInfo(name = "artist_id")
    val artistId: Long? = null,
    
    // Fingerprinting and deduplication
    @ColumnInfo(name = "audio_fingerprint")
    val audioFingerprint: String? = null,
    
    @ColumnInfo(name = "musicbrainz_track_id")
    val musicBrainzTrackId: String? = null,
    
    @ColumnInfo(name = "musicbrainz_recording_id")
    val musicBrainzRecordingId: String? = null,
    
    // Streaming/Cloud
    @ColumnInfo(name = "is_streaming")
    val isStreaming: Boolean = false,
    
    @ColumnInfo(name = "streaming_url")
    val streamingUrl: String? = null,
    
    @ColumnInfo(name = "cloud_sync_status")
    val cloudSyncStatus: String? = null, // SYNCED, PENDING, ERROR
    
    // Additional metadata
    @ColumnInfo(name = "language")
    val language: String? = null,
    
    @ColumnInfo(name = "isrc")
    val isrc: String? = null, // International Standard Recording Code
    
    @ColumnInfo(name = "copyright")
    val copyright: String? = null,
    
    @ColumnInfo(name = "publisher")
    val publisher: String? = null,
    
    // Status flags
    @ColumnInfo(name = "is_corrupted")
    val isCorrupted: Boolean = false,
    
    @ColumnInfo(name = "needs_metadata_refresh")
    val needsMetadataRefresh: Boolean = false,
    
    @ColumnInfo(name = "is_hidden")
    val isHidden: Boolean = false
)
