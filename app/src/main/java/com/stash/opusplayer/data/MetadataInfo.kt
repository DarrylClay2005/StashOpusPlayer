package com.stash.opusplayer.data

import androidx.room.Entity
import androidx.room.PrimaryKey

@Entity(tableName = "metadata_cache")
data class MetadataInfo(
    @PrimaryKey
    val filePath: String,
    val fileName: String,
    val duration: Long = 0L,
    val bitrate: Int = 0,
    val sampleRate: Int = 0,
    val format: String = "",
    val mimeType: String = "",
    val fileSize: Long = 0L,
    val lastModified: Long = 0L,
    val lastScanned: Long = System.currentTimeMillis(),
    // Additional technical metadata
    val channels: Int = 0,
    val bitsPerSample: Int = 0,
    val codec: String = "",
    val quality: String = "",
    // Error tracking
    val hasErrors: Boolean = false,
    val errorMessage: String? = null
)