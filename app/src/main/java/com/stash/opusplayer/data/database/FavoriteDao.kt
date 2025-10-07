package com.stash.opusplayer.data.database

import androidx.room.*
import kotlinx.coroutines.flow.Flow

@Dao
interface FavoriteDao {
    
    @Query("SELECT * FROM favorites ORDER BY dateAdded DESC")
    fun getAllFavorites(): Flow<List<FavoriteEntity>>
    
    @Query("SELECT * FROM favorites WHERE songId = :songId")
    suspend fun getFavorite(songId: Long): FavoriteEntity?
    
    @Query("SELECT EXISTS(SELECT 1 FROM favorites WHERE songId = :songId)")
    suspend fun isFavorite(songId: Long): Boolean
    
    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insertFavorite(favorite: FavoriteEntity)
    
    @Delete
    suspend fun deleteFavorite(favorite: FavoriteEntity)
    
    @Query("DELETE FROM favorites WHERE songId = :songId")
    suspend fun deleteFavoriteById(songId: Long)
    
    @Query("DELETE FROM favorites")
    suspend fun deleteAllFavorites()
}
