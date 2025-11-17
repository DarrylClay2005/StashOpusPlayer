package com.stash.opusplayer.music.data.database.daos

import androidx.room.*
import com.stash.opusplayer.music.data.database.entities.AlbumEntity
import kotlinx.coroutines.flow.Flow

@Dao
interface AlbumDao {
    @Query("SELECT * FROM albums ORDER BY title ASC")
    fun getAllAlbums(): Flow<List<AlbumEntity>>
    
    @Query("SELECT * FROM albums WHERE id = :albumId")
    suspend fun getAlbumById(albumId: Long): AlbumEntity?
    
    @Query("SELECT * FROM albums WHERE artist = :artist ORDER BY year DESC")
    fun getAlbumsByArtist(artist: String): Flow<List<AlbumEntity>>
    
    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insertAlbum(album: AlbumEntity): Long
    
    @Update
    suspend fun updateAlbum(album: AlbumEntity)
    
    @Delete
    suspend fun deleteAlbum(album: AlbumEntity)
    
    @Query("SELECT COUNT(*) FROM albums")
    suspend fun getAlbumCount(): Int
    
    @Query("SELECT * FROM albums WHERE artist_id = :artistId ORDER BY year DESC")
    suspend fun getAlbumsByArtist(artistId: Long): List<AlbumEntity>
}

