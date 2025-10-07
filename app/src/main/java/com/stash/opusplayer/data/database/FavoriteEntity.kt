package com.stash.opusplayer.data.database

import androidx.room.Entity
import androidx.room.PrimaryKey

@Entity(tableName = "favorites")
data class FavoriteEntity(
    @PrimaryKey val songId: Long,
    val title: String,
    val artist: String,
    val album: String,
    val path: String,
    val dateAdded: Long = System.currentTimeMillis()
)
