package com.stash.opusplayer.music.domain.models

import com.stash.opusplayer.music.data.database.entities.TrackEntity

/**
 * Track - Domain model representing a music track
 * 
 * This is the business logic layer representation of a track,
 * separate from database entities for clean architecture
 */
data class Track(
    val id: TrackId,
    val title: String,
    val artist: String,
    val album: String,
    val albumArtist: String?,
    val composer: String?,
    val genre: String?,
    val year: Int?,
    val trackNumber: Int?,
    val discNumber: Int?,
    
    // File info
    val path: String,
    val uri: String,
    val fileSize: Long,
    val mimeType: String,
    val codec: String?,
    val bitrate: Int?,
    val sampleRate: Int?,
    val channels: Int?,
    val bitDepth: Int?,
    
    // Duration and timing
    val duration: Long,
    val dateAdded: Long,
    val dateModified: Long,
    val lastPlayed: Long?,
    
    // Album art
    val albumArtUri: String?,
    val hasEmbeddedArt: Boolean,
    
    // User data
    val playCount: Int,
    val skipCount: Int,
    val isFavorite: Boolean,
    val rating: Float,
    val lastPosition: Long,
    
    // Quality metrics
    val quality: AudioQuality?,
    val dynamicRange: Float?,
    val loudness: Float?,
    val replayGainTrack: Float?,
    val replayGainAlbum: Float?,
    
    // AI metadata
    val aiGenre: String?,
    val aiMood: String?,
    val aiEnergy: Float?,
    val aiTempo: Float?,
    val aiKey: String?,
    val aiTags: List<String>,
    
    // Lyrics
    val hasLyrics: Boolean,
    val lyrics: String?,
    val comment: String?,
    
    // IDs
    val albumId: Long?,
    val artistId: Long?,
    
    // Fingerprinting
    val audioFingerprint: String?,
    val musicBrainzTrackId: String?,
    val musicBrainzRecordingId: String?,
    
    // Streaming
    val isStreaming: Boolean,
    val streamingUrl: String?,
    val cloudSyncStatus: CloudSyncStatus?,
    
    // Additional
    val language: String?,
    val isrc: String?,
    val copyright: String?,
    val publisher: String?,
    
    // Status
    val isCorrupted: Boolean,
    val needsMetadataRefresh: Boolean,
    val isHidden: Boolean
) {
    val displayTitle: String
        get() = if (title.isNotBlank()) title else path.substringAfterLast('/')
    
    val displayArtist: String
        get() = artist.ifBlank { "Unknown Artist" }
    
    val displayAlbum: String
        get() = album.ifBlank { "Unknown Album" }
    
    val durationFormatted: String
        get() {
            val seconds = duration / 1000
            val minutes = seconds / 60
            val secs = seconds % 60
            return String.format("%d:%02d", minutes, secs)
        }
    
    val qualityLabel: String
        get() = when (quality) {
            AudioQuality.HI_RES -> "Hi-Res"
            AudioQuality.LOSSLESS -> "Lossless"
            AudioQuality.LOSSY_HIGH -> "High"
            AudioQuality.LOSSY_MEDIUM -> "Medium"
            AudioQuality.LOSSY_LOW -> "Low"
            null -> "Unknown"
        }
}

@JvmInline
value class TrackId(val value: String)

enum class AudioQuality {
    HI_RES,      // > 16/44.1 or high bitrate
    LOSSLESS,    // FLAC, ALAC, WAV, etc.
    LOSSY_HIGH,  // 320kbps+
    LOSSY_MEDIUM,// 192-319kbps
    LOSSY_LOW    // < 192kbps
}

enum class CloudSyncStatus {
    SYNCED,
    PENDING,
    ERROR,
    NOT_SYNCED
}

/**
 * Extension function to convert TrackEntity to domain Track
 */
fun TrackEntity.toDomainModel(): Track {
    return Track(
        id = TrackId(id.toString()),
        title = title,
        artist = artist,
        album = album,
        albumArtist = albumArtist,
        composer = composer,
        genre = genre,
        year = year,
        trackNumber = trackNumber,
        discNumber = discNumber,
        path = path,
        uri = uri,
        fileSize = fileSize,
        mimeType = mimeType,
        codec = codec,
        bitrate = bitrate,
        sampleRate = sampleRate,
        channels = channels,
        bitDepth = bitDepth,
        duration = duration,
        dateAdded = dateAdded,
        dateModified = dateModified,
        lastPlayed = lastPlayed,
        albumArtUri = albumArtUri,
        hasEmbeddedArt = hasEmbeddedArt,
        playCount = playCount,
        skipCount = skipCount,
        isFavorite = isFavorite,
        rating = rating,
        lastPosition = lastPosition,
        quality = quality?.let { AudioQuality.valueOf(it) },
        dynamicRange = dynamicRange,
        loudness = loudness,
        replayGainTrack = replayGainTrack,
        replayGainAlbum = replayGainAlbum,
        aiGenre = aiGenre,
        aiMood = aiMood,
        aiEnergy = aiEnergy,
        aiTempo = aiTempo,
        aiKey = aiKey,
        aiTags = aiTags?.split(",")?.filter { it.isNotBlank() } ?: emptyList(),
        hasLyrics = hasLyrics,
        lyrics = lyrics,
        comment = comment,
        albumId = albumId,
        artistId = artistId,
        audioFingerprint = audioFingerprint,
        musicBrainzTrackId = musicBrainzTrackId,
        musicBrainzRecordingId = musicBrainzRecordingId,
        isStreaming = isStreaming,
        streamingUrl = streamingUrl,
        cloudSyncStatus = cloudSyncStatus?.let { CloudSyncStatus.valueOf(it) },
        language = language,
        isrc = isrc,
        copyright = copyright,
        publisher = publisher,
        isCorrupted = isCorrupted,
        needsMetadataRefresh = needsMetadataRefresh,
        isHidden = isHidden
    )
}

/**
 * Extension function to convert domain Track to TrackEntity
 */
fun Track.toEntity(): TrackEntity {
    return TrackEntity(
        id = id.value.toLongOrNull() ?: 0L,
        title = title,
        artist = artist,
        album = album,
        albumArtist = albumArtist,
        composer = composer,
        genre = genre,
        year = year,
        trackNumber = trackNumber,
        discNumber = discNumber,
        path = path,
        uri = uri,
        fileSize = fileSize,
        mimeType = mimeType,
        codec = codec,
        bitrate = bitrate,
        sampleRate = sampleRate,
        channels = channels,
        bitDepth = bitDepth,
        duration = duration,
        dateAdded = dateAdded,
        dateModified = dateModified,
        lastPlayed = lastPlayed,
        albumArtUri = albumArtUri,
        hasEmbeddedArt = hasEmbeddedArt,
        playCount = playCount,
        skipCount = skipCount,
        isFavorite = isFavorite,
        rating = rating,
        lastPosition = lastPosition,
        quality = quality?.name,
        dynamicRange = dynamicRange,
        loudness = loudness,
        replayGainTrack = replayGainTrack,
        replayGainAlbum = replayGainAlbum,
        aiGenre = aiGenre,
        aiMood = aiMood,
        aiEnergy = aiEnergy,
        aiTempo = aiTempo,
        aiKey = aiKey,
        aiTags = aiTags.joinToString(","),
        hasLyrics = hasLyrics,
        lyrics = lyrics,
        comment = comment,
        albumId = albumId,
        artistId = artistId,
        audioFingerprint = audioFingerprint,
        musicBrainzTrackId = musicBrainzTrackId,
        musicBrainzRecordingId = musicBrainzRecordingId,
        isStreaming = isStreaming,
        streamingUrl = streamingUrl,
        cloudSyncStatus = cloudSyncStatus?.name,
        language = language,
        isrc = isrc,
        copyright = copyright,
        publisher = publisher,
        isCorrupted = isCorrupted,
        needsMetadataRefresh = needsMetadataRefresh,
        isHidden = isHidden
    )
}
