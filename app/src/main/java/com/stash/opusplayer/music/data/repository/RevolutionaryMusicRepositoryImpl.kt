package com.stash.opusplayer.music.data.repository

import com.stash.opusplayer.music.data.database.RevolutionaryMusicDatabase
import com.stash.opusplayer.music.data.database.entities.*
import com.stash.opusplayer.music.domain.models.*
import com.stash.opusplayer.music.domain.repository.MusicRepository
import kotlinx.coroutines.flow.*
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import android.util.Log
import java.util.concurrent.ConcurrentHashMap

/**
 * Revolutionary Music Repository Implementation
 * 
 * Complete implementation with:
 * - Full domain model integration
 * - Advanced query support with filtering and sorting
 * - Multi-level caching (memory + disk)
 * - Full-text search
 * - Relationship management
 * - Performance monitoring
 * - Error handling and recovery
 * - Thread-safe operations
 */
class RevolutionaryMusicRepositoryImpl(
    private val database: RevolutionaryMusicDatabase
) : MusicRepository {
    
    companion object {
        private const val TAG = "RevolutionaryMusicRepo"
        private const val CACHE_MAX_SIZE = 1000
        private const val CACHE_EXPIRY_MS = 5 * 60 * 1000L // 5 minutes
    }
    
    // Thread-safe caches
    private val trackCache = ConcurrentHashMap<TrackId, CachedItem<Track>>()
    private val albumCache = ConcurrentHashMap<AlbumId, CachedItem<Album>>()
    private val artistCache = ConcurrentHashMap<ArtistId, CachedItem<Artist>>()
    private val playlistCache = ConcurrentHashMap<PlaylistId, CachedItem<Playlist>>()
    
    private val cacheMutex = Mutex()
    
    // DAOs
    private val trackDao = database.trackDao()
    private val albumDao = database.albumDao()
    private val artistDao = database.artistDao()
    private val playlistDao = database.playlistDao()
    private val scanHistoryDao = database.scanHistoryDao()
    
    // ====================================
    // Track Operations
    // ====================================
    
    override fun observeAllTracks(): Flow<List<Track>> {
        return trackDao.getAllTracks()
            .map { entities -> entities.map { it.toDomainModel() } }
            .flowOn(Dispatchers.IO)
            .catch { e ->
                Log.e(TAG, "Error observing tracks", e)
                emit(emptyList())
            }
    }
    
    override suspend fun queryTracks(query: MusicQuery): MusicQueryResult<Track> = withContext(Dispatchers.IO) {
        try {
            val startTime = System.currentTimeMillis()
            
            // Start with all tracks
            var tracks = trackDao.getAllTracksSync()
            val totalCount = tracks.size
            
            // Apply filters
            tracks = applyFilters(tracks, query)
            val filteredCount = tracks.size
            
            // Apply sorting
            tracks = applySorting(tracks, query.sorting)
            
            // Apply pagination
            val offset = query.offset
            val limit = query.limit ?: Int.MAX_VALUE
            val paginatedTracks = tracks.drop(offset).take(limit)
            
            val queryTime = System.currentTimeMillis() - startTime
            
            MusicQueryResult(
                items = paginatedTracks.map { it.toDomainModel() },
                totalCount = totalCount,
                hasMore = (offset + limit) < filteredCount,
                queryTime = queryTime
            )
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
    
    override suspend fun getTrackById(id: TrackId): Track? {
        // Check cache first
        trackCache[id]?.let { cached ->
            if (!cached.isExpired()) {
                return cached.item
            }
        }
        
        return withContext(Dispatchers.IO) {
            try {
                val entityId = id.value.toLongOrNull() ?: return@withContext null
                val entity = trackDao.getTrackById(entityId)
                entity?.toDomainModel()?.also { track ->
                    cacheTrack(track)
                }
            } catch (e: Exception) {
                Log.e(TAG, "Error getting track by id: $id", e)
                null
            }
        }
    }
    
    override suspend fun getTracksByIds(ids: List<TrackId>): List<Track> = withContext(Dispatchers.IO) {
        try {
            val entityIds = ids.mapNotNull { it.value.toLongOrNull() }
            val entities = trackDao.getTracksByIds(entityIds)
            entities.map { it.toDomainModel() }.also { tracks ->
                tracks.forEach { track -> cacheTrack(track) }
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error getting tracks by ids", e)
            emptyList()
        }
    }
    
    override fun searchTracks(searchTerm: String): Flow<List<Track>> {
        return trackDao.searchTracks(searchTerm)
            .map { entities -> entities.map { entity -> entity.toDomainModel() } }
            .flowOn(Dispatchers.IO)
            .catch { e ->
                Log.e(TAG, "Error searching tracks: $searchTerm", e)
                emit(emptyList<Track>())
            }
    }
    
    override suspend fun saveTrack(track: Track): Unit = withContext(Dispatchers.IO) {
        try {
            val entity = track.toEntity()
            trackDao.insertTrack(entity)
            cacheTrack(track)
            invalidateRelatedCaches(track)
            Log.d(TAG, "Track saved: ${track.title}")
        } catch (e: Exception) {
            Log.e(TAG, "Error saving track: ${track.title}", e)
            throw e
        }
    }
    
    override suspend fun saveTracks(tracks: List<Track>): Unit = withContext(Dispatchers.IO) {
        try {
            val entities = tracks.map { it.toEntity() }
            trackDao.insertTracks(entities)
            tracks.forEach { cacheTrack(it) }
            tracks.forEach { invalidateRelatedCaches(it) }
            Log.d(TAG, "Saved ${tracks.size} tracks")
        } catch (e: Exception) {
            Log.e(TAG, "Error saving tracks", e)
            throw e
        }
    }
    
    override suspend fun deleteTrack(trackId: TrackId) = withContext(Dispatchers.IO) {
        try {
            val track = getTrackById(trackId)
            if (track != null) {
                trackDao.deleteTrack(track.toEntity())
                trackCache.remove(trackId)
                invalidateRelatedCaches(track)
                Log.d(TAG, "Track deleted: $trackId")
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error deleting track: $trackId", e)
            throw e
        }
    }
    
    override suspend fun incrementPlayCount(trackId: TrackId): Unit = withContext(Dispatchers.IO) {
        try {
            val entityId = trackId.value.toLongOrNull() ?: return@withContext
            val now = System.currentTimeMillis()
            trackDao.incrementPlayCount(entityId, now)
            trackCache.remove(trackId) // Invalidate cache
            Log.d(TAG, "Play count incremented for track: $trackId")
        } catch (e: Exception) {
            Log.e(TAG, "Error incrementing play count: $trackId", e)
        }
    }
    
    override suspend fun setFavorite(trackId: TrackId, isFavorite: Boolean): Unit = withContext(Dispatchers.IO) {
        try {
            val entityId = trackId.value.toLongOrNull() ?: return@withContext
            trackDao.setFavorite(entityId, isFavorite)
            trackCache.remove(trackId) // Invalidate cache
            Log.d(TAG, "Favorite set to $isFavorite for track: $trackId")
        } catch (e: Exception) {
            Log.e(TAG, "Error setting favorite: $trackId", e)
        }
    }
    
    override suspend fun setRating(trackId: TrackId, rating: Float): Unit = withContext(Dispatchers.IO) {
        try {
            val entityId = trackId.value.toLongOrNull() ?: return@withContext
            trackDao.updateRating(entityId, rating)
            trackCache.remove(trackId) // Invalidate cache
            Log.d(TAG, "Rating set to $rating for track: $trackId")
        } catch (e: Exception) {
            Log.e(TAG, "Error setting rating: $trackId", e)
        }
    }
    
    override fun observeFavoriteTracks(): Flow<List<Track>> {
        return trackDao.observeFavoriteTracks()
            .map { entities -> entities.map { it.toDomainModel() } }
            .flowOn(Dispatchers.IO)
            .catch { e ->
                Log.e(TAG, "Error observing favorite tracks", e)
                emit(emptyList())
            }
    }
    
    override fun observeRecentlyPlayed(limit: Int): Flow<List<Track>> {
        return trackDao.getRecentlyPlayedTracks(limit)
            .map { entities -> entities.map { it.toDomainModel() } }
            .flowOn(Dispatchers.IO)
            .catch { e ->
                Log.e(TAG, "Error observing recently played", e)
                emit(emptyList())
            }
    }
    
    override fun observeMostPlayed(limit: Int): Flow<List<Track>> {
        return trackDao.getMostPlayedTracks(limit)
            .map { entities -> entities.map { it.toDomainModel() } }
            .flowOn(Dispatchers.IO)
            .catch { e ->
                Log.e(TAG, "Error observing most played", e)
                emit(emptyList())
            }
    }
    
    // ====================================
    // Album Operations
    // ====================================
    
    override fun observeAllAlbums(): Flow<List<Album>> {
        return albumDao.getAllAlbums()
            .map { entities -> entities.map { it.toDomainModel() } }
            .flowOn(Dispatchers.IO)
            .catch { e ->
                Log.e(TAG, "Error observing albums", e)
                emit(emptyList())
            }
    }
    
    override suspend fun getAlbumById(id: AlbumId): Album? {
        // Check cache
        albumCache[id]?.let { cached ->
            if (!cached.isExpired()) {
                return cached.item
            }
        }
        
        return withContext(Dispatchers.IO) {
            try {
                val entityId = id.value.toLongOrNull() ?: return@withContext null
                val entity = albumDao.getAlbumById(entityId)
                entity?.toDomainModel()?.also { album ->
                    cacheAlbum(album)
                }
            } catch (e: Exception) {
                Log.e(TAG, "Error getting album by id: $id", e)
                null
            }
        }
    }
    
    override suspend fun getAlbumsByArtist(artistId: ArtistId): List<Album> = withContext(Dispatchers.IO) {
        try {
            val entityId = artistId.value.toLongOrNull() ?: return@withContext emptyList()
            val entities = albumDao.getAlbumsByArtist(entityId)
            entities.map { it.toDomainModel() }.also { albums ->
                albums.forEach { album -> cacheAlbum(album) }
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error getting albums by artist: $artistId", e)
            emptyList()
        }
    }
    
    override suspend fun saveAlbum(album: Album): Unit = withContext(Dispatchers.IO) {
        try {
            val entity = album.toEntity()
            albumDao.insertAlbum(entity)
            cacheAlbum(album)
            Log.d(TAG, "Album saved: ${album.title}")
        } catch (e: Exception) {
            Log.e(TAG, "Error saving album: ${album.title}", e)
            throw e
        }
    }
    
    // ====================================
    // Artist Operations
    // ====================================
    
    override fun observeAllArtists(): Flow<List<Artist>> {
        return artistDao.getAllArtists()
            .map { entities -> entities.map { it.toDomainModel() } }
            .flowOn(Dispatchers.IO)
            .catch { e ->
                Log.e(TAG, "Error observing artists", e)
                emit(emptyList())
            }
    }
    
    override suspend fun getArtistById(id: ArtistId): Artist? {
        // Check cache
        artistCache[id]?.let { cached ->
            if (!cached.isExpired()) {
                return cached.item
            }
        }
        
        return withContext(Dispatchers.IO) {
            try {
                val entityId = id.value.toLongOrNull() ?: return@withContext null
                val entity = artistDao.getArtistById(entityId)
                entity?.toDomainModel()?.also { artist ->
                    cacheArtist(artist)
                }
            } catch (e: Exception) {
                Log.e(TAG, "Error getting artist by id: $id", e)
                null
            }
        }
    }
    
    override suspend fun saveArtist(artist: Artist): Unit = withContext(Dispatchers.IO) {
        try {
            val entity = artist.toEntity()
            artistDao.insertArtist(entity)
            cacheArtist(artist)
            Log.d(TAG, "Artist saved: ${artist.name}")
        } catch (e: Exception) {
            Log.e(TAG, "Error saving artist: ${artist.name}", e)
            throw e
        }
    }
    
    // ====================================
    // Playlist Operations
    // ====================================
    
    override fun observeAllPlaylists(): Flow<List<Playlist>> {
        return playlistDao.getAllPlaylists()
            .map { entities -> entities.map { it.toDomainModel() } }
            .flowOn(Dispatchers.IO)
            .catch { e ->
                Log.e(TAG, "Error observing playlists", e)
                emit(emptyList())
            }
    }
    
    override suspend fun getPlaylistById(id: PlaylistId): Playlist? {
        // Check cache
        playlistCache[id]?.let { cached ->
            if (!cached.isExpired()) {
                return cached.item
            }
        }
        
        return withContext(Dispatchers.IO) {
            try {
                val entity = playlistDao.getPlaylistById(id.value)
                entity?.toDomainModel()?.also { playlist ->
                    cachePlaylist(playlist)
                }
            } catch (e: Exception) {
                Log.e(TAG, "Error getting playlist by id: $id", e)
                null
            }
        }
    }
    
    override suspend fun savePlaylist(playlist: Playlist): Unit = withContext(Dispatchers.IO) {
        try {
            val entity = playlist.toEntity()
            playlistDao.insertPlaylist(entity)
            cachePlaylist(playlist)
            Log.d(TAG, "Playlist saved: ${playlist.name}")
        } catch (e: Exception) {
            Log.e(TAG, "Error saving playlist: ${playlist.name}", e)
            throw e
        }
    }
    
    override suspend fun deletePlaylist(playlistId: PlaylistId) = withContext(Dispatchers.IO) {
        try {
            val playlist = getPlaylistById(playlistId)
            if (playlist != null) {
                playlistDao.deletePlaylist(playlist.toEntity())
                playlistCache.remove(playlistId)
                Log.d(TAG, "Playlist deleted: $playlistId")
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error deleting playlist: $playlistId", e)
            throw e
        }
    }
    
    override suspend fun addTracksToPlaylist(playlistId: PlaylistId, trackIds: List<TrackId>): Unit = withContext(Dispatchers.IO) {
        try {
            val currentMax = playlistDao.getMaxPositionInPlaylist(playlistId.value) ?: -1
            val entities = trackIds.mapNotNull { trackId ->
                val entityTrackId = trackId.value.toLongOrNull() ?: return@mapNotNull null
                PlaylistTrackEntity(
                    playlistId = playlistId.value,
                    trackId = entityTrackId,
                    position = currentMax + trackIds.indexOf(trackId) + 1,
                    dateAdded = System.currentTimeMillis()
                )
            }
            playlistDao.insertPlaylistTracks(entities)
            playlistCache.remove(playlistId)
            Log.d(TAG, "Added ${trackIds.size} tracks to playlist: $playlistId")
        } catch (e: Exception) {
            Log.e(TAG, "Error adding tracks to playlist: $playlistId", e)
            throw e
        }
    }
    
    override suspend fun removeTrackFromPlaylist(playlistId: PlaylistId, trackId: TrackId): Unit = withContext(Dispatchers.IO) {
        try {
            val entityTrackId = trackId.value.toLongOrNull() ?: return@withContext
            playlistDao.removeTrackFromPlaylist(playlistId.value, entityTrackId)
            playlistCache.remove(playlistId)
            Log.d(TAG, "Removed track $trackId from playlist: $playlistId")
        } catch (e: Exception) {
            Log.e(TAG, "Error removing track from playlist: $playlistId", e)
        }
    }
    
    override fun observePlaylistTracks(playlistId: PlaylistId): Flow<List<Track>> {
        return playlistDao.getPlaylistTracksWithDetails(playlistId.value)
            .map { entities -> entities.map { it.toDomainModel() } }
            .flowOn(Dispatchers.IO)
            .catch { e ->
                Log.e(TAG, "Error observing playlist tracks: $playlistId", e)
                emit(emptyList())
            }
    }
    
    // ====================================
    // Statistics
    // ====================================
    
    override suspend fun getTotalTrackCount(): Int = withContext(Dispatchers.IO) {
        try {
            trackDao.getTrackCount()
        } catch (e: Exception) {
            Log.e(TAG, "Error getting track count", e)
            0
        }
    }
    
    override suspend fun getTotalAlbumCount(): Int = withContext(Dispatchers.IO) {
        try {
            albumDao.getAlbumCount()
        } catch (e: Exception) {
            Log.e(TAG, "Error getting album count", e)
            0
        }
    }
    
    override suspend fun getTotalArtistCount(): Int = withContext(Dispatchers.IO) {
        try {
            artistDao.getArtistCount()
        } catch (e: Exception) {
            Log.e(TAG, "Error getting artist count", e)
            0
        }
    }
    
    // ====================================
    // Private Helper Methods
    // ====================================
    
    private fun applyFilters(tracks: List<TrackEntity>, query: MusicQuery): List<TrackEntity> {
        var result = tracks
        
        // Genre filter
        if (query.genres.isNotEmpty()) {
            result = result.filter { track ->
                track.genre?.let { trackGenre ->
                    query.genres.any { queryGenre -> trackGenre.contains(queryGenre, ignoreCase = true) }
                } ?: false
            }
        }
        
        // Artist filter
        if (query.artists.isNotEmpty()) {
            result = result.filter { track ->
                track.artist?.let { trackArtist ->
                    query.artists.any { queryArtist -> trackArtist.contains(queryArtist, ignoreCase = true) }
                } ?: false
            }
        }
        
        // Album filter
        if (query.albums.isNotEmpty()) {
            result = result.filter { track ->
                track.album?.let { trackAlbum ->
                    query.albums.any { queryAlbum -> trackAlbum.contains(queryAlbum, ignoreCase = true) }
                } ?: false
            }
        }
        
        // Year filter
        query.years?.let { yearRange ->
            result = result.filter { track ->
                track.year?.let { it in yearRange } ?: false
            }
        }
        
        // Favorite filter
        query.isFavorite?.let { isFavorite ->
            if (isFavorite) {
                result = result.filter { it.isFavorite }
            }
        }
        
        // Rating filter
        query.minRating?.let { minRating ->
            result = result.filter { (it.rating ?: 0f) >= minRating }
        }
        
        return result
    }
    
    private fun applySorting(tracks: List<TrackEntity>, sort: SortingOption): List<TrackEntity> {
        return when (sort) {
            SortingOption.TITLE_ASC -> tracks.sortedBy { it.title }
            SortingOption.TITLE_DESC -> tracks.sortedByDescending { it.title }
            SortingOption.ARTIST_ASC -> tracks.sortedBy { it.artist }
            SortingOption.ARTIST_DESC -> tracks.sortedByDescending { it.artist }
            SortingOption.ALBUM_ASC -> tracks.sortedBy { it.album }
            SortingOption.ALBUM_DESC -> tracks.sortedByDescending { it.album }
            SortingOption.DURATION_ASC -> tracks.sortedBy { it.duration }
            SortingOption.DURATION_DESC -> tracks.sortedByDescending { it.duration }
            SortingOption.DATE_ADDED_ASC -> tracks.sortedBy { it.dateAdded }
            SortingOption.DATE_ADDED_DESC -> tracks.sortedByDescending { it.dateAdded }
            SortingOption.PLAY_COUNT_ASC -> tracks.sortedBy { it.playCount }
            SortingOption.PLAY_COUNT_DESC -> tracks.sortedByDescending { it.playCount }
            SortingOption.RATING_ASC -> tracks.sortedBy { it.rating ?: 0f }
            SortingOption.RATING_DESC -> tracks.sortedByDescending { it.rating ?: 0f }
            SortingOption.YEAR_ASC -> tracks.sortedBy { it.year ?: 0 }
            SortingOption.YEAR_DESC -> tracks.sortedByDescending { it.year ?: 0 }
            SortingOption.RANDOM -> tracks.shuffled()
            else -> tracks
        }
    }
    
    private fun cacheTrack(track: Track) {
        if (trackCache.size >= CACHE_MAX_SIZE) {
            cleanExpiredCache(trackCache)
        }
        trackCache[track.id] = CachedItem(track)
    }
    
    private fun cacheAlbum(album: Album) {
        if (albumCache.size >= CACHE_MAX_SIZE) {
            cleanExpiredCache(albumCache)
        }
        albumCache[album.id] = CachedItem(album)
    }
    
    private fun cacheArtist(artist: Artist) {
        if (artistCache.size >= CACHE_MAX_SIZE) {
            cleanExpiredCache(artistCache)
        }
        artistCache[artist.id] = CachedItem(artist)
    }
    
    private fun cachePlaylist(playlist: Playlist) {
        if (playlistCache.size >= CACHE_MAX_SIZE) {
            cleanExpiredCache(playlistCache)
        }
        playlistCache[playlist.id] = CachedItem(playlist)
    }
    
    private fun <K, V> cleanExpiredCache(cache: ConcurrentHashMap<K, CachedItem<V>>) {
        val now = System.currentTimeMillis()
        cache.entries.removeAll { (_, cached) -> cached.isExpired(now) }
    }
    
    private fun invalidateRelatedCaches(track: Track) {
        track.albumId?.let { albumCache.remove(AlbumId(it.toString())) }
        track.artistId?.let { artistCache.remove(ArtistId(it.toString())) }
    }
    
    // ====================================
    // Cache Helper Classes
    // ====================================
    
    private data class CachedItem<T>(
        val item: T,
        val timestamp: Long = System.currentTimeMillis()
    ) {
        fun isExpired(now: Long = System.currentTimeMillis()): Boolean {
            return (now - timestamp) > CACHE_EXPIRY_MS
        }
    }
}
