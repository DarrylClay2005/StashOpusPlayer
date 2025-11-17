package com.stash.opusplayer.music.data.database.entities

import androidx.room.ColumnInfo
import androidx.room.Entity
import androidx.room.Fts4

@Fts4(contentEntity = TrackEntity::class)
@Entity(tableName = "tracks_fts")
data class TrackFtsEntity(
    @ColumnInfo(name = "title")
    val title: String,
    
    @ColumnInfo(name = "artist")
    val artist: String,
    
    @ColumnInfo(name = "album")
    val album: String,
    
    @ColumnInfo(name = "genre")
    val genre: String?,
    
    @ColumnInfo(name = "composer")
    val composer: String?
)
