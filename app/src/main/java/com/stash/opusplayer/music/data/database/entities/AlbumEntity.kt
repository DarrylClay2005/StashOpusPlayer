package com.stash.opusplayer.music.data.database.entities

import androidx.room.ColumnInfo
import androidx.room.Entity
import androidx.room.Index
import androidx.room.PrimaryKey

/**
 * Album Entity - Complete album information
 */
@Entity(
    tableName = "albums",
    indices = [
        Index(value = ["title"]),
        Index(value = ["artist"]),
        Index(value = ["artist_id"]),
        Index(value = ["year"]),
        Index(value = ["artist", "year"])
    ]
)
data class AlbumEntity(
    @PrimaryKey(autoGenerate = true)
    @ColumnInfo(name = "id")
    val id: Long = 0,
    
    @ColumnInfo(name = "title")
    val title: String,
    
    @ColumnInfo(name = "artist")
    val artist: String,
    
    @ColumnInfo(name = "artist_id")
    val artistId: Long? = null,
    
    @ColumnInfo(name = "year")
    val year: Int? = null,
    
    @ColumnInfo(name = "genre")
    val genre: String? = null,
    
    @ColumnInfo(name = "album_art_uri")
    val albumArtUri: String? = null,
    
    @ColumnInfo(name = "track_count")
    val trackCount: Int = 0,
    
    @ColumnInfo(name = "total_duration")
    val totalDuration: Long = 0,
    
    @ColumnInfo(name = "date_added")
    val dateAdded: Long,
    
    @ColumnInfo(name = "date_modified")
    val dateModified: Long,
    
    @ColumnInfo(name = "play_count")
    val playCount: Int = 0,
    
    @ColumnInfo(name = "is_favorite")
    val isFavorite: Boolean = false,
    
    @ColumnInfo(name = "rating")
    val rating: Float = 0f,
    
    @ColumnInfo(name = "musicbrainz_album_id")
    val musicBrainzAlbumId: String? = null,
    
    @ColumnInfo(name = "musicbrainz_release_group_id")
    val musicBrainzReleaseGroupId: String? = null,
    
    @ColumnInfo(name = "record_label")
    val recordLabel: String? = null,
    
    @ColumnInfo(name = "release_type")
    val releaseType: String? = null, // ALBUM, EP, SINGLE, COMPILATION
    
    @ColumnInfo(name = "country")
    val country: String? = null
)
