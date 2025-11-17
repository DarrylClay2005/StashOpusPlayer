package com.stash.opusplayer.music.domain.models

/**
 * Comprehensive music query system for advanced filtering and sorting
 */
data class MusicQuery(
    val searchTerm: String = "",
    val genres: List<String> = emptyList(),
    val artists: List<String> = emptyList(),
    val albums: List<String> = emptyList(),
    val years: IntRange? = null,
    val minRating: Float? = null,
    val isFavorite: Boolean? = null,
    val hasLyrics: Boolean? = null,
    val qualityLevels: List<AudioQuality> = emptyList(),
    val sorting: SortingOption = SortingOption.TITLE_ASC,
    val limit: Int? = null,
    val offset: Int = 0
)

enum class SortingOption {
    TITLE_ASC, TITLE_DESC,
    ARTIST_ASC, ARTIST_DESC,
    ALBUM_ASC, ALBUM_DESC,
    YEAR_ASC, YEAR_DESC,
    DURATION_ASC, DURATION_DESC,
    RATING_ASC, RATING_DESC,
    PLAY_COUNT_ASC, PLAY_COUNT_DESC,
    DATE_ADDED_ASC, DATE_ADDED_DESC,
    DATE_MODIFIED_ASC, DATE_MODIFIED_DESC,
    LAST_PLAYED_ASC, LAST_PLAYED_DESC,
    RANDOM
}

data class MusicQueryResult<T>(
    val items: List<T>,
    val totalCount: Int,
    val hasMore: Boolean,
    val queryTime: Long
)

enum class CacheInvalidationType {
    TRACKS, ALBUMS, ARTISTS, PLAYLISTS, ALL
}
