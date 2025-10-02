package com.stash.stashwave.data

import android.os.Parcelable
import kotlinx.parcelize.Parcelize

@Parcelize
data class YouTubeVideo(
    val id: String,
    val title: String,
    val description: String,
    val channelTitle: String,
    val channelId: String,
    val thumbnailUrl: String,
    val highResThumbnailUrl: String?,
    val duration: String?,
    val viewCount: String?,
    val publishedAt: String,
    val url: String
) : Parcelable {
    val formattedUrl: String
        get() = "https://www.youtube.com/watch?v=$id"
        
    // Compatibility property for streaming activity
    val thumbnails: List<YouTubeThumbnail>
        get() = listOfNotNull(
            thumbnailUrl.takeIf { it.isNotEmpty() }?.let { 
                YouTubeThumbnail(it, 320, 180) 
            },
            highResThumbnailUrl?.takeIf { it.isNotEmpty() }?.let { 
                YouTubeThumbnail(it, 1280, 720) 
            }
        )
}

@Parcelize
data class YouTubeSearchResult(
    val videos: List<YouTubeVideo>,
    val nextPageToken: String?,
    val totalResults: Int
) : Parcelable

@Parcelize
data class YouTubeThumbnail(
    val url: String,
    val width: Int,
    val height: Int
) : Parcelable

data class DownloadProgress(
    val videoId: String,
    val progress: Int, // 0-100
    val status: DownloadStatus,
    val filePath: String? = null,
    val error: String? = null
)

enum class DownloadStatus {
    PENDING,
    DOWNLOADING,
    COMPLETED,
    FAILED,
    CANCELLED
}

data class AudioFormat(
    val formatId: String,
    val extension: String,
    val quality: String,
    val bitrate: String?,
    val codec: String,
    val fileSize: String?
) {
    val displayName: String
        get() = "$extension ${quality}${bitrate?.let { " ($it kbps)" } ?: ""}"
}

data class DownloadRequest(
    val video: YouTubeVideo,
    val downloadPath: String,
    val selectedFormat: AudioFormat,
    val audioOnly: Boolean = true
)
