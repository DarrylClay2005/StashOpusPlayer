package com.stash.opusplayer.music.library

import android.content.Context
import android.util.Log
import com.stash.opusplayer.music.domain.models.*
import com.stash.opusplayer.music.domain.repository.MusicRepository
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.*
import java.util.concurrent.ConcurrentHashMap

/**
 * Revolutionary Library Manager
 * 
 * High-level music library management with:
 * - Smart library organization
 * - Collection management
 * - Playlist operations
 * - Search and discovery
 * - Library statistics
 * - Batch operations
 * - Background synchronization
 */
class RevolutionaryLibraryManager(
    private val context: Context,
    private val repository: MusicRepository
) {
    companion object {
        private const val TAG = "RevLibraryManager"
        private const val BATCH_SIZE = 100
    }

    private val scope = CoroutineScope(Dispatchers.Default + SupervisorJob())
    private val _libraryState = MutableStateFlow<LibraryState>(LibraryState.Idle)
    val libraryState: StateFlow<LibraryState> = _libraryState.asStateFlow()

    // Collections cache
    private val collections = ConcurrentHashMap<String, MusicCollection>()

    // ====================================
    // Library Access
    // ====================================

    fun getAllTracks(): Flow<List<Track>> {
        return repository.observeAllTracks()
            .catch { e ->
                Log.e(TAG, "Error observing all tracks", e)
                emit(emptyList())
            }
    }

    fun getAllAlbums(): Flow<List<Album>> {
        return repository.observeAllAlbums()
            .catch { e ->
                Log.e(TAG, "Error observing all albums", e)
                emit(emptyList())
            }
    }

    fun getAllArtists(): Flow<List<Artist>> {
        return repository.observeAllArtists()
            .catch { e ->
                Log.e(TAG, "Error observing all artists", e)
                emit(emptyList())
            }
    }

    fun getAllPlaylists(): Flow<List<Playlist>> {
        return repository.observeAllPlaylists()
            .catch { e ->
                Log.e(TAG, "Error observing all playlists", e)
                emit(emptyList())
            }
    }

    // ====================================
    // Track Operations
    // ====================================

    suspend fun getTrack(id: TrackId): Track? {
        return try {
            repository.getTrackById(id)
        } catch (e: Exception) {
            Log.e(TAG, "Error getting track: $id", e)
            null
        }
    }

    suspend fun getTracks(ids: List<TrackId>): List<Track> {
        return try {
            repository.getTracksByIds(ids)
        } catch (e: Exception) {
            Log.e(TAG, "Error getting tracks", e)
            emptyList()
        }
    }

    fun searchTracks(query: String): Flow<List<Track>> {
        if (query.isBlank()) {
            return flowOf(emptyList())
        }
        return repository.searchTracks(query)
            .catch { e ->
                Log.e(TAG, "Error searching tracks: $query", e)
                emit(emptyList())
            }
    }

    suspend fun queryTracks(query: MusicQuery): MusicQueryResult<Track> {
        return try {
            repository.queryTracks(query)
        } catch (e: Exception) {
            Log.e(TAG, "Error querying tracks", e)
            MusicQueryResult(
                items = emptyList(),
                totalCount = 0,
                hasMore = false,
                queryTime = 0
            )
        }
    }

    suspend fun saveTracks(tracks: List<Track>) {
        try {
            _libraryState.value = LibraryState.Saving(tracks.size)
            repository.saveTracks(tracks)
            _libraryState.value = LibraryState.Idle
            Log.d(TAG, "Saved ${tracks.size} tracks")
        } catch (e: Exception) {
            Log.e(TAG, "Error saving tracks", e)
            _libraryState.value = LibraryState.Error(e.message ?: "Failed to save tracks")
        }
    }

    suspend fun deleteTrack(trackId: TrackId) {
        try {
            repository.deleteTrack(trackId)
            Log.d(TAG, "Deleted track: $trackId")
        } catch (e: Exception) {
            Log.e(TAG, "Error deleting track: $trackId", e)
            throw e
        }
    }

    suspend fun updateTrackRating(trackId: TrackId, rating: Float) {
        try {
            repository.setRating(trackId, rating.coerceIn(0f, 5f))
            Log.d(TAG, "Updated rating for track: $trackId to $rating")
        } catch (e: Exception) {
            Log.e(TAG, "Error updating rating", e)
        }
    }

    suspend fun toggleFavorite(trackId: TrackId, isFavorite: Boolean) {
        try {
            repository.setFavorite(trackId, isFavorite)
            Log.d(TAG, "Toggled favorite for track: $trackId to $isFavorite")
        } catch (e: Exception) {
            Log.e(TAG, "Error toggling favorite", e)
        }
    }

    fun getFavoriteTracks(): Flow<List<Track>> {
        return repository.observeFavoriteTracks()
            .catch { e ->
                Log.e(TAG, "Error observing favorite tracks", e)
                emit(emptyList())
            }
    }

    fun getRecentlyPlayed(limit: Int = 50): Flow<List<Track>> {
        return repository.observeRecentlyPlayed(limit)
            .catch { e ->
                Log.e(TAG, "Error observing recently played", e)
                emit(emptyList())
            }
    }

    fun getMostPlayed(limit: Int = 50): Flow<List<Track>> {
        return repository.observeMostPlayed(limit)
            .catch { e ->
                Log.e(TAG, "Error observing most played", e)
                emit(emptyList())
            }
    }

    // ====================================
    // Album Operations
    // ====================================

    suspend fun getAlbum(id: AlbumId): Album? {
        return try {
            repository.getAlbumById(id)
        } catch (e: Exception) {
            Log.e(TAG, "Error getting album: $id", e)
            null
        }
    }

    suspend fun getAlbumsByArtist(artistId: ArtistId): List<Album> {
        return try {
            repository.getAlbumsByArtist(artistId)
        } catch (e: Exception) {
            Log.e(TAG, "Error getting albums by artist: $artistId", e)
            emptyList()
        }
    }

    suspend fun saveAlbum(album: Album) {
        try {
            repository.saveAlbum(album)
            Log.d(TAG, "Saved album: ${album.title}")
        } catch (e: Exception) {
            Log.e(TAG, "Error saving album", e)
            throw e
        }
    }

    // ====================================
    // Artist Operations
    // ====================================

    suspend fun getArtist(id: ArtistId): Artist? {
        return try {
            repository.getArtistById(id)
        } catch (e: Exception) {
            Log.e(TAG, "Error getting artist: $id", e)
            null
        }
    }

    suspend fun saveArtist(artist: Artist) {
        try {
            repository.saveArtist(artist)
            Log.d(TAG, "Saved artist: ${artist.name}")
        } catch (e: Exception) {
            Log.e(TAG, "Error saving artist", e)
            throw e
        }
    }

    // ====================================
    // Playlist Operations
    // ====================================

    suspend fun getPlaylist(id: PlaylistId): Playlist? {
        return try {
            repository.getPlaylistById(id)
        } catch (e: Exception) {
            Log.e(TAG, "Error getting playlist: $id", e)
            null
        }
    }

    fun getPlaylistTracks(playlistId: PlaylistId): Flow<List<Track>> {
        return repository.observePlaylistTracks(playlistId)
            .catch { e ->
                Log.e(TAG, "Error observing playlist tracks: $playlistId", e)
                emit(emptyList())
            }
    }

    suspend fun createPlaylist(
        name: String,
        description: String? = null,
        trackIds: List<TrackId> = emptyList()
    ): PlaylistId {
        return try {
            val playlistId = PlaylistId(System.currentTimeMillis().toString())
            val playlist = Playlist(
                id = playlistId,
                name = name,
                description = description,
                imageUrl = null,
                isPublic = false,
                isSystem = false,
                isShuffle = false,
                repeatMode = RepeatMode.OFF,
                isAutoGenerated = false,
                totalTracks = trackIds.size,
                totalDuration = 0L,
                playCount = 0,
                lastPlayed = null,
                creationDate = System.currentTimeMillis(),
                dateModified = System.currentTimeMillis(),
                tags = emptyList(),
                autoUpdateRules = null
            )
            
            repository.savePlaylist(playlist)
            
            if (trackIds.isNotEmpty()) {
                repository.addTracksToPlaylist(playlistId, trackIds)
            }
            
            Log.d(TAG, "Created playlist: $name with ${trackIds.size} tracks")
            playlistId
        } catch (e: Exception) {
            Log.e(TAG, "Error creating playlist", e)
            throw e
        }
    }

    suspend fun addTracksToPlaylist(playlistId: PlaylistId, trackIds: List<TrackId>) {
        try {
            repository.addTracksToPlaylist(playlistId, trackIds)
            Log.d(TAG, "Added ${trackIds.size} tracks to playlist: $playlistId")
        } catch (e: Exception) {
            Log.e(TAG, "Error adding tracks to playlist", e)
            throw e
        }
    }

    suspend fun removeTrackFromPlaylist(playlistId: PlaylistId, trackId: TrackId) {
        try {
            repository.removeTrackFromPlaylist(playlistId, trackId)
            Log.d(TAG, "Removed track from playlist: $playlistId")
        } catch (e: Exception) {
            Log.e(TAG, "Error removing track from playlist", e)
            throw e
        }
    }

    suspend fun deletePlaylist(playlistId: PlaylistId) {
        try {
            repository.deletePlaylist(playlistId)
            Log.d(TAG, "Deleted playlist: $playlistId")
        } catch (e: Exception) {
            Log.e(TAG, "Error deleting playlist", e)
            throw e
        }
    }

    // ====================================
    // Smart Collections
    // ====================================

    suspend fun getCollection(id: String): MusicCollection? {
        return collections[id] ?: buildCollection(id)
    }

    private suspend fun buildCollection(id: String): MusicCollection? {
        return try {
            when (id) {
                "recently_added" -> buildRecentlyAddedCollection()
                "top_rated" -> buildTopRatedCollection()
                "most_played" -> buildMostPlayedCollection()
                "favorites" -> buildFavoritesCollection()
                else -> null
            }?.also {
                collections[id] = it
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error building collection: $id", e)
            null
        }
    }

    private suspend fun buildRecentlyAddedCollection(): MusicCollection {
        val query = MusicQuery(
            sorting = SortingOption.DATE_ADDED_DESC,
            limit = 100
        )
        val result = repository.queryTracks(query)
        return MusicCollection(
            id = "recently_added",
            name = "Recently Added",
            description = "Your newest tracks",
            tracks = result.items
        )
    }

    private suspend fun buildTopRatedCollection(): MusicCollection {
        val query = MusicQuery(
            minRating = 4.0f,
            sorting = SortingOption.RATING_DESC,
            limit = 100
        )
        val result = repository.queryTracks(query)
        return MusicCollection(
            id = "top_rated",
            name = "Top Rated",
            description = "Your highest rated tracks",
            tracks = result.items
        )
    }

    private suspend fun buildMostPlayedCollection(): MusicCollection {
        val query = MusicQuery(
            sorting = SortingOption.PLAY_COUNT_DESC,
            limit = 100
        )
        val result = repository.queryTracks(query)
        return MusicCollection(
            id = "most_played",
            name = "Most Played",
            description = "Your most played tracks",
            tracks = result.items
        )
    }

    private suspend fun buildFavoritesCollection(): MusicCollection {
        val query = MusicQuery(
            isFavorite = true,
            sorting = SortingOption.DATE_ADDED_DESC,
            limit = 500
        )
        val result = repository.queryTracks(query)
        return MusicCollection(
            id = "favorites",
            name = "Favorites",
            description = "Your favorite tracks",
            tracks = result.items
        )
    }

    fun refreshCollections() {
        scope.launch {
            collections.clear()
            listOf("recently_added", "top_rated", "most_played", "favorites").forEach {
                buildCollection(it)
            }
        }
    }

    // ====================================
    // Library Statistics
    // ====================================

    suspend fun getLibraryStats(): LibraryStatistics {
        return try {
            val trackCount = repository.getTotalTrackCount()
            val albumCount = repository.getTotalAlbumCount()
            val artistCount = repository.getTotalArtistCount()
            
            LibraryStatistics(
                totalTracks = trackCount,
                totalAlbums = albumCount,
                totalArtists = artistCount,
                totalPlaylists = 0, // Will be calculated from flow
                totalDuration = 0L, // Will be calculated from tracks
                totalSize = 0L, // Will be calculated from tracks
                lastScanDate = 0L
            )
        } catch (e: Exception) {
            Log.e(TAG, "Error getting library stats", e)
            LibraryStatistics(0, 0, 0, 0, 0L, 0L, 0L)
        }
    }

    // ====================================
    // Batch Operations
    // ====================================

    suspend fun batchUpdateRatings(updates: Map<TrackId, Float>) {
        _libraryState.value = LibraryState.BatchProcessing(updates.size, 0)
        
        updates.entries.chunked(BATCH_SIZE).forEachIndexed { index, chunk ->
            chunk.forEach { (trackId, rating) ->
                try {
                    repository.setRating(trackId, rating)
                } catch (e: Exception) {
                    Log.e(TAG, "Error updating rating for $trackId", e)
                }
            }
            
            val processed = (index + 1) * BATCH_SIZE
            _libraryState.value = LibraryState.BatchProcessing(updates.size, processed)
        }
        
        _libraryState.value = LibraryState.Idle
        Log.d(TAG, "Batch updated ${updates.size} ratings")
    }

    suspend fun batchToggleFavorites(trackIds: List<TrackId>, isFavorite: Boolean) {
        _libraryState.value = LibraryState.BatchProcessing(trackIds.size, 0)
        
        trackIds.chunked(BATCH_SIZE).forEachIndexed { index, chunk ->
            chunk.forEach { trackId ->
                try {
                    repository.setFavorite(trackId, isFavorite)
                } catch (e: Exception) {
                    Log.e(TAG, "Error toggling favorite for $trackId", e)
                }
            }
            
            val processed = (index + 1) * BATCH_SIZE
            _libraryState.value = LibraryState.BatchProcessing(trackIds.size, processed)
        }
        
        _libraryState.value = LibraryState.Idle
        Log.d(TAG, "Batch toggled favorites for ${trackIds.size} tracks")
    }

    // ====================================
    // Discovery & Recommendations
    // ====================================

    suspend fun getRecommendedTracks(basedOn: TrackId, limit: Int = 20): List<Track> {
        return try {
            val baseTrack = repository.getTrackById(basedOn) ?: return emptyList()
            
            // Find similar tracks by genre and artist
            val query = MusicQuery(
                genres = listOfNotNull(baseTrack.genre).filter { it.isNotBlank() },
                artists = listOfNotNull(baseTrack.artist).filter { it.isNotBlank() },
                sorting = SortingOption.RATING_DESC,
                limit = limit + 1 // +1 to exclude base track
            )
            
            val result = repository.queryTracks(query)
            result.items.filter { it.id != basedOn }.take(limit)
        } catch (e: Exception) {
            Log.e(TAG, "Error getting recommendations", e)
            emptyList()
        }
    }

    suspend fun getRandomTracks(limit: Int = 50): List<Track> {
        return try {
            val query = MusicQuery(
                sorting = SortingOption.RANDOM,
                limit = limit
            )
            val result = repository.queryTracks(query)
            result.items
        } catch (e: Exception) {
            Log.e(TAG, "Error getting random tracks", e)
            emptyList()
        }
    }

    // ====================================
    // Cleanup
    // ====================================

    fun cleanup() {
        scope.cancel()
        collections.clear()
        Log.d(TAG, "Library manager cleaned up")
    }
}

// ====================================
// Data Classes
// ====================================

sealed class LibraryState {
    object Idle : LibraryState()
    data class Saving(val count: Int) : LibraryState()
    data class Loading(val message: String) : LibraryState()
    data class BatchProcessing(val total: Int, val processed: Int) : LibraryState()
    data class Error(val message: String) : LibraryState()
}

data class MusicCollection(
    val id: String,
    val name: String,
    val description: String,
    val tracks: List<Track>
)

data class LibraryStatistics(
    val totalTracks: Int,
    val totalAlbums: Int,
    val totalArtists: Int,
    val totalPlaylists: Int,
    val totalDuration: Long,
    val totalSize: Long,
    val lastScanDate: Long
)
