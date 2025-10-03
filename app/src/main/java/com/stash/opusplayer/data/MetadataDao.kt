package com.stash.stashwave.data

import androidx.room.*
import kotlinx.coroutines.flow.Flow

@Dao
interface MetadataDao {
    
    @Query("SELECT * FROM metadata_cache WHERE filePath = :filePath")
    suspend fun getMetadata(filePath: String): MetadataInfo?
    
    @Query("SELECT * FROM metadata_cache WHERE filePath = :filePath")
    fun getMetadataFlow(filePath: String): Flow<MetadataInfo?>
    
    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insertMetadata(metadata: MetadataInfo)
    
    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insertAll(metadataList: List<MetadataInfo>)
    
    @Query("DELETE FROM metadata_cache WHERE filePath = :filePath")
    suspend fun deleteMetadata(filePath: String)
    
    @Query("DELETE FROM metadata_cache WHERE filePath IN (:filePaths)")
    suspend fun deleteMetadata(filePaths: List<String>)
    
    @Query("SELECT COUNT(*) FROM metadata_cache")
    suspend fun getMetadataCount(): Int
    
    @Query("SELECT * FROM metadata_cache WHERE hasErrors = 1")
    suspend fun getErrorMetadata(): List<MetadataInfo>
    
    @Query("SELECT * FROM metadata_cache WHERE lastScanned < :timestamp")
    suspend fun getOutdatedMetadata(timestamp: Long): List<MetadataInfo>
    
    @Query("UPDATE metadata_cache SET hasErrors = 0, errorMessage = NULL WHERE filePath = :filePath")
    suspend fun clearError(filePath: String)
    
    @Query("DELETE FROM metadata_cache WHERE lastScanned < :timestamp")
    suspend fun cleanupOldEntries(timestamp: Long)
}