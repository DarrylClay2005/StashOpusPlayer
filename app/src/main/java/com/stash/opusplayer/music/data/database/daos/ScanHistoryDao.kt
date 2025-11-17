package com.stash.opusplayer.music.data.database.daos

import androidx.room.*
import com.stash.opusplayer.music.data.database.entities.ScanHistoryEntity
import kotlinx.coroutines.flow.Flow

@Dao
interface ScanHistoryDao {
    @Query("SELECT * FROM scan_history ORDER BY timestamp DESC LIMIT :limit")
    fun getRecentScans(limit: Int = 20): Flow<List<ScanHistoryEntity>>
    
    @Insert
    suspend fun insertScan(scan: ScanHistoryEntity): Long
    
    @Query("DELETE FROM scan_history WHERE timestamp < :timestamp")
    suspend fun deleteOldScans(timestamp: Long)
    
    @Query("DELETE FROM scan_history WHERE timestamp < :cutoffTimestamp")
    suspend fun deleteOldScanHistory(cutoffTimestamp: Long): Int
    
    @Query("SELECT COUNT(*) FROM scan_history WHERE error_count = 0")
    suspend fun getSuccessfulScanCount(): Int
    
    @Query("SELECT COUNT(*) FROM scan_history WHERE error_count > 0")
    suspend fun getFailedScanCount(): Int
}
