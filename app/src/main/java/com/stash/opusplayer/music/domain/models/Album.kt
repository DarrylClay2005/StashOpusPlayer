package com.stash.opusplayer.music.domain.models

import com.stash.opusplayer.music.data.database.entities.AlbumEntity

data class Album(
    val id: AlbumId,
    val title: String,
    val artist: String,
    val artistId: Long?,
    val year: Int?,
    val genre: String?,
    val albumArtUri: String?,
    val trackCount: Int,
    val totalDuration: Long,
    val dateAdded: Long,
    val dateModified: Long,
    val playCount: Int,
    val isFavorite: Boolean,
    val rating: Float,
    val musicBrainzAlbumId: String?,
    val musicBrainzReleaseGroupId: String?,
    val recordLabel: String?,
    val releaseType: ReleaseType?,
    val country: String?
) {
    val displayTitle: String get() = title.ifBlank { "Unknown Album" }
    val displayArtist: String get() = artist.ifBlank { "Unknown Artist" }
}

@JvmInline
value class AlbumId(val value: String)

enum class ReleaseType {
    ALBUM, EP, SINGLE, COMPILATION
}

fun AlbumEntity.toDomainModel() = Album(
    id = AlbumId(id.toString()),
    title = title,
    artist = artist,
    artistId = artistId,
    year = year,
    genre = genre,
    albumArtUri = albumArtUri,
    trackCount = trackCount,
    totalDuration = totalDuration,
    dateAdded = dateAdded,
    dateModified = dateModified,
    playCount = playCount,
    isFavorite = isFavorite,
    rating = rating,
    musicBrainzAlbumId = musicBrainzAlbumId,
    musicBrainzReleaseGroupId = musicBrainzReleaseGroupId,
    recordLabel = recordLabel,
    releaseType = releaseType?.let { ReleaseType.valueOf(it) },
    country = country
)

fun Album.toEntity() = AlbumEntity(
    id = id.value.toLongOrNull() ?: 0L,
    title = title,
    artist = artist,
    artistId = artistId,
    year = year,
    genre = genre,
    albumArtUri = albumArtUri,
    trackCount = trackCount,
    totalDuration = totalDuration,
    dateAdded = dateAdded,
    dateModified = dateModified,
    playCount = playCount,
    isFavorite = isFavorite,
    rating = rating,
    musicBrainzAlbumId = musicBrainzAlbumId,
    musicBrainzReleaseGroupId = musicBrainzReleaseGroupId,
    recordLabel = recordLabel,
    releaseType = releaseType?.name,
    country = country
)
