package com.stash.opusplayer.music.data.database.daos

import androidx.room.*
import com.stash.opusplayer.music.data.database.entities.TrackEntity
import kotlinx.coroutines.flow.Flow

@Dao
interface TrackDao {
    @Query("SELECT * FROM tracks ORDER BY title ASC")
    fun getAllTracks(): Flow<List<TrackEntity>>
    
    @Query("SELECT * FROM tracks WHERE id = :trackId")
    suspend fun getTrackById(trackId: Long): TrackEntity?
    
    @Query("SELECT * FROM tracks WHERE path = :path")
    suspend fun getTrackByPath(path: String): TrackEntity?
    
    @Query("SELECT * FROM tracks WHERE artist = :artist ORDER BY album, track_number")
    fun getTracksByArtist(artist: String): Flow<List<TrackEntity>>
    
    @Query("SELECT * FROM tracks WHERE album = :album ORDER BY track_number")
    fun getTracksByAlbum(album: String): Flow<List<TrackEntity>>
    
    @Query("SELECT * FROM tracks WHERE is_favorite = 1 ORDER BY date_modified DESC")
    fun getFavoriteTracks(): Flow<List<TrackEntity>>
    
    @Query("SELECT * FROM tracks ORDER BY last_played DESC LIMIT :limit")
    fun getRecentlyPlayedTracks(limit: Int = 50): Flow<List<TrackEntity>>
    
    @Query("SELECT * FROM tracks ORDER BY play_count DESC LIMIT :limit")
    fun getMostPlayedTracks(limit: Int = 50): Flow<List<TrackEntity>>
    
    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insertTrack(track: TrackEntity): Long
    
    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insertTracks(tracks: List<TrackEntity>): List<Long>
    
    @Update
    suspend fun updateTrack(track: TrackEntity)
    
    @Delete
    suspend fun deleteTrack(track: TrackEntity)
    
    @Query("DELETE FROM tracks WHERE id = :trackId")
    suspend fun deleteTrackById(trackId: Long)
    
    @Query("UPDATE tracks SET play_count = play_count + 1, last_played = :timestamp WHERE id = :trackId")
    suspend fun incrementPlayCount(trackId: Long, timestamp: Long)
    
    @Query("UPDATE tracks SET is_favorite = :isFavorite WHERE id = :trackId")
    suspend fun setFavorite(trackId: Long, isFavorite: Boolean)
    
    @Query("UPDATE tracks SET rating = :rating WHERE id = :trackId")
    suspend fun setRating(trackId: Long, rating: Float)
    
    @Query("UPDATE tracks SET rating = :rating WHERE id = :trackId")
    suspend fun updateRating(trackId: Long, rating: Float)
    
    @Query("SELECT COUNT(*) FROM tracks")
    suspend fun getTrackCount(): Int
    
    @Query("SELECT SUM(duration) FROM tracks")
    suspend fun getTotalDuration(): Long?
    
    @Query("SELECT SUM(file_size) FROM tracks")
    suspend fun getTotalFileSize(): Long?
    
    @Query("SELECT * FROM tracks WHERE is_favorite = 1 ORDER BY date_modified DESC")
    fun observeFavoriteTracks(): Flow<List<TrackEntity>>
    
    @Query("DELETE FROM tracks WHERE path NOT IN (SELECT path FROM scan_history)")
    suspend fun deleteOrphanedTracks(): Int
    
    @Query("SELECT * FROM tracks ORDER BY title ASC")
    suspend fun getAllTracksSync(): List<TrackEntity>
    
    @Query("SELECT * FROM tracks WHERE id IN (:trackIds)")
    suspend fun getTracksByIds(trackIds: List<Long>): List<TrackEntity>
    
    @Query("""SELECT tracks.* FROM tracks 
        JOIN tracks_fts ON tracks.id = tracks_fts.rowid 
        WHERE tracks_fts MATCH :searchTerm
        ORDER BY tracks.title ASC""")
    fun searchTracks(searchTerm: String): Flow<List<TrackEntity>>
}
