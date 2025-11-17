package com.stash.opusplayer.music.data.database.entities

import androidx.room.ColumnInfo
import androidx.room.Entity
import androidx.room.Index
import androidx.room.PrimaryKey

@Entity(
    tableName = "artists",
    indices = [Index(value = ["name"], unique = true)]
)
data class ArtistEntity(
    @PrimaryKey(autoGenerate = true)
    val id: Long = 0,
    
    @ColumnInfo(name = "name")
    val name: String,
    
    @ColumnInfo(name = "album_count")
    val albumCount: Int = 0,
    
    @ColumnInfo(name = "track_count")
    val trackCount: Int = 0,
    
    @ColumnInfo(name = "artist_art_uri")
    val artistArtUri: String? = null,
    
    @ColumnInfo(name = "bio")
    val bio: String? = null,
    
    @ColumnInfo(name = "musicbrainz_artist_id")
    val musicBrainzArtistId: String? = null,
    
    @ColumnInfo(name = "is_favorite")
    val isFavorite: Boolean = false,
    
    @ColumnInfo(name = "date_added")
    val dateAdded: Long
)
