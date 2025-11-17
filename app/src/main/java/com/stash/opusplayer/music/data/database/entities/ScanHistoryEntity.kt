package com.stash.opusplayer.music.data.database.entities

import androidx.room.ColumnInfo
import androidx.room.Entity
import androidx.room.Index
import androidx.room.PrimaryKey

@Entity(
    tableName = "scan_history",
    indices = [Index(value = ["path", "timestamp"])]
)
data class ScanHistoryEntity(
    @PrimaryKey(autoGenerate = true)
    val id: Long = 0,
    
    @ColumnInfo(name = "path")
    val path: String,
    
    @ColumnInfo(name = "timestamp")
    val timestamp: Long,
    
    @ColumnInfo(name = "files_scanned")
    val filesScanned: Int,
    
    @ColumnInfo(name = "files_added")
    val filesAdded: Int,
    
    @ColumnInfo(name = "files_updated")
    val filesUpdated: Int,
    
    @ColumnInfo(name = "files_removed")
    val filesRemoved: Int,
    
    @ColumnInfo(name = "duration_ms")
    val durationMs: Long,
    
    @ColumnInfo(name = "error_count")
    val errorCount: Int = 0,
    
    @ColumnInfo(name = "error_details")
    val errorDetails: String? = null
)
