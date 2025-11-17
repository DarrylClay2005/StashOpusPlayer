package com.stash.opusplayer.music.data.database.daos

import androidx.room.*
import com.stash.opusplayer.music.data.database.entities.ArtistEntity
import kotlinx.coroutines.flow.Flow

@Dao
interface ArtistDao {
    @Query("SELECT * FROM artists ORDER BY name ASC")
    fun getAllArtists(): Flow<List<ArtistEntity>>
    
    @Query("SELECT * FROM artists WHERE id = :artistId")
    suspend fun getArtistById(artistId: Long): ArtistEntity?
    
    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insertArtist(artist: ArtistEntity): Long
    
    @Update
    suspend fun updateArtist(artist: ArtistEntity)
    
    @Delete
    suspend fun deleteArtist(artist: ArtistEntity)
    
    @Query("SELECT COUNT(*) FROM artists")
    suspend fun getArtistCount(): Int
}

