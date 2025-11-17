package com.stash.opusplayer.music.domain.models

import com.stash.opusplayer.music.data.database.entities.ArtistEntity

data class Artist(
    val id: ArtistId,
    val name: String,
    val albumCount: Int,
    val trackCount: Int,
    val artistArtUri: String?,
    val bio: String?,
    val musicBrainzArtistId: String?,
    val isFavorite: Boolean,
    val dateAdded: Long
) {
    val displayName: String get() = name.ifBlank { "Unknown Artist" }
}

@JvmInline
value class ArtistId(val value: String)

fun ArtistEntity.toDomainModel() = Artist(
    id = ArtistId(id.toString()),
    name = name,
    albumCount = albumCount,
    trackCount = trackCount,
    artistArtUri = artistArtUri,
    bio = bio,
    musicBrainzArtistId = musicBrainzArtistId,
    isFavorite = isFavorite,
    dateAdded = dateAdded
)

fun Artist.toEntity() = ArtistEntity(
    id = id.value.toLongOrNull() ?: 0L,
    name = name,
    albumCount = albumCount,
    trackCount = trackCount,
    artistArtUri = artistArtUri,
    bio = bio,
    musicBrainzArtistId = musicBrainzArtistId,
    isFavorite = isFavorite,
    dateAdded = dateAdded
)
