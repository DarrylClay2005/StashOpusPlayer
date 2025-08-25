package com.stash.opusplayer.data

import android.os.Parcelable
import kotlinx.parcelize.Parcelize

@Parcelize
data class Song(
    val id: Long,
    val title: String,
    val artist: String,
    val album: String,
    val duration: Long,
    val path: String,
    val albumId: Long = -1,
    val artistId: Long = -1,
    val dateAdded: Long = 0,
    val size: Long = 0,
    val mimeType: String = "",
    val albumArt: String? = null,
    val track: Int = 0,
    val year: String = "",
    val genre: String = "",
    val bitrate: Int = 0,
    val sampleRate: Int = 0,
    val isFavorite: Boolean = false
) : Parcelable {
    
    val displayName: String
        get() = if (title.isBlank()) path.substringAfterLast("/") else title
    
    val artistName: String
        get() = if (artist.isBlank()) "Unknown Artist" else artist
        
    val albumName: String
        get() = if (album.isBlank()) "Unknown Album" else album
        
    val durationText: String
        get() {
            val minutes = (duration / 1000) / 60
            val seconds = (duration / 1000) % 60
            return String.format("%d:%02d", minutes, seconds)
        }
}
