package com.stash.opusplayer.utils

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.media.MediaMetadataRetriever
import android.net.Uri
import android.util.Base64
import android.util.Log
import com.stash.opusplayer.data.Song
import java.io.ByteArrayOutputStream
import java.io.File

class MetadataExtractor(private val context: Context) {
    
    companion object {
        private const val TAG = "MetadataExtractor"
        private const val MAX_ART_DIMENSION = 512 // px, cap decoded size to reduce memory
        private const val JPEG_QUALITY = 70 // compress more to keep memory and storage low
    }
    
    fun extractMetadata(song: Song): Song {
        return extractMetadata(song, forceArtworkExtraction = true)
    }
    
    fun extractMetadata(song: Song, forceArtworkExtraction: Boolean = false): Song {
        val retriever = MediaMetadataRetriever()
        return try {
            if (song.path.startsWith("content://")) {
                retriever.setDataSource(context, Uri.parse(song.path))
            } else {
                retriever.setDataSource(song.path)
            }
            
            val title = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_TITLE)
            val artist = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_ARTIST)
            val album = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_ALBUM)
            val duration = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)?.toLongOrNull() ?: 0L
            val track = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_CD_TRACK_NUMBER)?.toIntOrNull() ?: 0
            val year = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_YEAR) ?: ""
            val genre = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_GENRE) ?: ""
            val bitrate = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_BITRATE)?.toIntOrNull() ?: 0
            
            // Extract album art and store a thumbnail in cache for fast future loads
            val albumArt = extractAlbumArt(retriever, song, forceArtworkExtraction)
            
            song.copy(
                title = title ?: song.title,
                artist = artist ?: song.artist,
                album = album ?: song.album,
                duration = if (duration > 0) duration else song.duration,
                track = track,
                year = year,
                genre = genre,
                bitrate = bitrate,
                albumArt = albumArt
            )
        } catch (e: Exception) {
            Log.e(TAG, "Error extracting metadata for ${song.path}", e)
            song
        } finally {
            try {
                retriever.release()
            } catch (e: Exception) {
                Log.e(TAG, "Error releasing metadata retriever", e)
            }
        }
    }
    
    private fun extractAlbumArt(retriever: MediaMetadataRetriever, song: Song, forceExtraction: Boolean = false): String? {
        return try {
            // Try multiple methods to extract artwork for better format compatibility
            var artBytes = retriever.embeddedPicture
            
            // For some formats, try alternative extraction methods
            if (artBytes == null || artBytes.isEmpty()) {
                artBytes = tryAlternativeArtworkExtraction(song.path)
            }
            
            Log.d(TAG, "Extracting artwork for ${song.displayName} (${getFileExtension(song.path)}) - embedded bytes: ${artBytes?.size ?: 0}")
            
            if (artBytes == null || artBytes.isEmpty()) {
                Log.d(TAG, "No embedded artwork found for ${song.displayName}")
                return null
            }

            // First decode bounds to compute an inSampleSize
            val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
            BitmapFactory.decodeByteArray(artBytes, 0, artBytes.size, bounds)
            val sampleSize = calculateInSampleSize(bounds, MAX_ART_DIMENSION, MAX_ART_DIMENSION)

            val options = BitmapFactory.Options().apply {
                inJustDecodeBounds = false
                inSampleSize = sampleSize
                inPreferredConfig = Bitmap.Config.RGB_565 // smaller than ARGB_8888
            }

            val bitmap = BitmapFactory.decodeByteArray(artBytes, 0, artBytes.size, options) ?: return null

            val stream = ByteArrayOutputStream(32 * 1024)
            try {
                bitmap.compress(Bitmap.CompressFormat.JPEG, JPEG_QUALITY, stream)
            } finally {
                // Release native memory ASAP
                try { bitmap.recycle() } catch (_: Throwable) {}
            }
            val compressedBytes = stream.toByteArray()

            // Save to on-device cache for fast reuse
            try {
val cache = com.stash.opusplayer.artwork.ArtworkCache(context)
                val outFile = cache.fileFor(song)
                if (!outFile.exists()) {
                    cache.saveJpeg(compressedBytes, outFile)
                }
            } catch (e: Exception) {
                Log.w(TAG, "Failed to write album art to cache", e)
            }

            // Use NO_WRAP to keep string compact
            val base64Art = Base64.encodeToString(compressedBytes, Base64.NO_WRAP)
            Log.d(TAG, "Successfully extracted artwork for ${song.displayName} - base64 length: ${base64Art.length}")
            base64Art
        } catch (oom: OutOfMemoryError) {
            Log.e(TAG, "OOM extracting album art", oom)
            null
        } catch (e: Exception) {
            Log.e(TAG, "Error extracting album art", e)
            null
        }
    }

    private fun calculateInSampleSize(options: BitmapFactory.Options, reqWidth: Int, reqHeight: Int): Int {
        val width = options.outWidth
        val height = options.outHeight
        var inSampleSize = 1
        if (height > reqHeight || width > reqWidth) {
            var halfHeight = height / 2
            var halfWidth = width / 2
            while ((halfHeight / inSampleSize) >= reqHeight && (halfWidth / inSampleSize) >= reqWidth) {
                inSampleSize *= 2
            }
        }
        if (inSampleSize <= 0) inSampleSize = 1
        return inSampleSize
    }
    
    private fun getFileExtension(path: String): String {
        return path.substringAfterLast('.', "").lowercase()
    }
    
    private fun tryAlternativeArtworkExtraction(filePath: String): ByteArray? {
        val extension = getFileExtension(filePath)
        Log.d(TAG, "Trying alternative artwork extraction for $extension file: $filePath")
        
        return when (extension) {
            "mp3" -> tryMp3ArtworkExtraction(filePath)
            "flac" -> tryFlacArtworkExtraction(filePath)
            "m4a", "mp4" -> tryMp4ArtworkExtraction(filePath)
            "opus", "ogg" -> tryOggOpusArtworkExtraction(filePath)
            else -> {
                Log.d(TAG, "No alternative extraction method for $extension")
                null
            }
        }
    }
    
    private fun tryMp3ArtworkExtraction(filePath: String): ByteArray? {
        return try {
            // Use additional MP3 tag reading library if available
            Log.d(TAG, "Attempting MP3-specific artwork extraction")
            val retriever = MediaMetadataRetriever()
            if (filePath.startsWith("content://")) {
                retriever.setDataSource(context, Uri.parse(filePath))
            } else {
                retriever.setDataSource(filePath)
            }
            
            // Try again with different approach - sometimes works on second attempt
            val artBytes = retriever.embeddedPicture
            retriever.release()
            artBytes
        } catch (e: Exception) {
            Log.w(TAG, "MP3 artwork extraction failed", e)
            null
        }
    }
    
    private fun tryFlacArtworkExtraction(filePath: String): ByteArray? {
        return try {
            Log.d(TAG, "Attempting FLAC-specific artwork extraction")
            // FLAC files sometimes need special handling
            val retriever = MediaMetadataRetriever()
            if (filePath.startsWith("content://")) {
                retriever.setDataSource(context, Uri.parse(filePath))
            } else {
                retriever.setDataSource(filePath)
            }
            
            val artBytes = retriever.embeddedPicture
            retriever.release()
            artBytes
        } catch (e: Exception) {
            Log.w(TAG, "FLAC artwork extraction failed", e)
            null
        }
    }
    
    private fun tryMp4ArtworkExtraction(filePath: String): ByteArray? {
        return try {
            Log.d(TAG, "Attempting M4A/MP4 artwork extraction")
            val retriever = MediaMetadataRetriever()
            if (filePath.startsWith("content://")) {
                retriever.setDataSource(context, Uri.parse(filePath))
            } else {
                retriever.setDataSource(filePath)
            }
            
            val artBytes = retriever.embeddedPicture
            retriever.release()
            artBytes
        } catch (e: Exception) {
            Log.w(TAG, "M4A/MP4 artwork extraction failed", e)
            null
        }
    }
    
    private fun tryOggOpusArtworkExtraction(filePath: String): ByteArray? {
        return try {
            Log.d(TAG, "Attempting OGG/OPUS artwork extraction")
            // OGG/OPUS files may need special handling
            val retriever = MediaMetadataRetriever()
            if (filePath.startsWith("content://")) {
                retriever.setDataSource(context, Uri.parse(filePath))
            } else {
                retriever.setDataSource(filePath)
            }
            
            val artBytes = retriever.embeddedPicture
            retriever.release()
            artBytes
        } catch (e: Exception) {
            Log.w(TAG, "OGG/OPUS artwork extraction failed", e)
            null
        }
    }
    
    fun decodeAlbumArt(albumArtBase64: String?): Bitmap? {
        return try {
            if (albumArtBase64.isNullOrEmpty()) return null
            val artBytes = Base64.decode(albumArtBase64, Base64.DEFAULT)
            BitmapFactory.decodeByteArray(artBytes, 0, artBytes.size)
        } catch (e: Exception) {
            Log.e(TAG, "Error decoding album art", e)
            null
        }
    }

    fun loadCachedArtwork(context: Context, song: Song, maxDim: Int = MAX_ART_DIMENSION): Bitmap? {
        return try {
            val cache = com.stash.opusplayer.artwork.ArtworkCache(context)
            // Try exact match
            cache.loadBitmapIfPresent(song, maxDim)
                ?: run {
                    // Try common album fallbacks for downloaded YouTube audio where album tag varies
                    val candidates = listOf("YouTube", "Unknown Album", "")
                    for (alb in candidates) {
                        val alt = song.copy(album = alb)
                        val bmp = cache.loadBitmapIfPresent(alt, maxDim)
                        if (bmp != null) return bmp
                    }
                    // Fallback to title-only cache key (helps when tags are Unknown Artist/Album)
                    cache.loadBitmapByTitleIfPresent(song.displayName, maxDim)
                }
        } catch (e: Exception) {
            Log.e(TAG, "Error loading cached artwork", e)
            null
        }
    }
    
    fun extractBasicInfo(filePath: String): Song? {
        val isContent = filePath.startsWith("content://")
        val file = if (!isContent) File(filePath) else null
        if (!isContent && (file == null || !file.exists())) return null
        
        val retriever = MediaMetadataRetriever()
        return try {
            if (isContent) {
                retriever.setDataSource(context, Uri.parse(filePath))
            } else {
                retriever.setDataSource(filePath)
            }
            
            val title = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_TITLE) 
                ?: (if (!isContent) file!!.nameWithoutExtension else Uri.parse(filePath).lastPathSegment?.substringBeforeLast('.') ?: "Unknown Title")
            val artist = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_ARTIST) 
                ?: "Unknown Artist"
            val album = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_ALBUM) 
                ?: "Unknown Album"
            val duration = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)?.toLongOrNull() ?: 0L
            
            // Extract album art for better thumbnails
            val albumArt = extractAlbumArt(retriever, Song(
                id = filePath.hashCode().toLong(),
                title = title,
                artist = artist,
                album = album,
                duration = duration,
                path = filePath,
                size = if (!isContent) file!!.length() else 0L,
                mimeType = if (!isContent) getMimeType(filePath) else "audio/*",
                dateAdded = if (!isContent) file!!.lastModified() else 0L
            ))
            
            Song(
                id = filePath.hashCode().toLong(),
                title = title,
                artist = artist,
                album = album,
                duration = duration,
                path = filePath,
                size = if (!isContent) file!!.length() else 0L,
                mimeType = if (!isContent) getMimeType(filePath) else "audio/*",
                dateAdded = if (!isContent) file!!.lastModified() else 0L,
                albumArt = albumArt
            )
        } catch (e: Exception) {
            // Fallback: build minimal Song so we still list files like .opus when retriever fails
            Log.w(TAG, "Retriever failed for $filePath, building minimal info", e)
            try {
                val title = if (isContent) {
                    Uri.parse(filePath).lastPathSegment?.substringBeforeLast('.') ?: "Unknown Title"
                } else {
                    file!!.nameWithoutExtension
                }
                return Song(
                    id = filePath.hashCode().toLong(),
                    title = title,
                    artist = "Unknown Artist",
                    album = "Unknown Album",
                    duration = 0L,
                    path = filePath,
                    size = if (!isContent) file!!.length() else 0L,
                    mimeType = if (!isContent) getMimeType(filePath) else "audio/*",
                    dateAdded = if (!isContent) file!!.lastModified() else 0L
                )
            } catch (ee: Exception) {
                Log.e(TAG, "Fallback failed for $filePath", ee)
                null
            }
        } finally {
            try {
                retriever.release()
            } catch (e: Exception) {
                Log.e(TAG, "Error releasing metadata retriever", e)
            }
        }
    }
    
    private fun getMimeType(filePath: String): String {
        val extension = filePath.substringAfterLast(".", "").lowercase()
        return when (extension) {
            "mp3" -> "audio/mpeg"
            "opus" -> "audio/opus"
            "ogg" -> "audio/ogg"
            "flac" -> "audio/flac"
            "m4a", "aac" -> "audio/mp4"
            "wav" -> "audio/wav"
            "wma" -> "audio/x-ms-wma"
            "webm" -> "audio/webm"
            "mp4" -> "video/mp4"
            "mkv" -> "video/x-matroska"
            "avi" -> "video/x-msvideo"
            else -> "audio/*"
        }
    }
    
    /**
     * Downloads YouTube thumbnail and returns Base64 encoded image
     */
    suspend fun downloadYouTubeThumbnail(videoId: String): String? {
        return try {
            // YouTube thumbnail URLs in order of preference (quality)
            val thumbnailUrls = listOf(
                "https://img.youtube.com/vi/$videoId/maxresdefault.jpg",
                "https://img.youtube.com/vi/$videoId/hqdefault.jpg",
                "https://img.youtube.com/vi/$videoId/mqdefault.jpg",
                "https://img.youtube.com/vi/$videoId/default.jpg"
            )
            
            val client = okhttp3.OkHttpClient.Builder()
                .connectTimeout(10, java.util.concurrent.TimeUnit.SECONDS)
                .readTimeout(15, java.util.concurrent.TimeUnit.SECONDS)
                .build()
            
            for (url in thumbnailUrls) {
                try {
                    val request = okhttp3.Request.Builder()
                        .url(url)
                        .addHeader("User-Agent", "Mozilla/5.0 (Android; Mobile; rv:40.0) Gecko/40.0 Firefox/40.0")
                        .build()
                    
                    val response = client.newCall(request).execute()
                    if (response.isSuccessful) {
                        val imageBytes = response.body?.bytes()
                        if (imageBytes != null && imageBytes.isNotEmpty()) {
                            // Process and optimize the thumbnail
                            val optimizedBytes = optimizeImage(imageBytes)
                            if (optimizedBytes != null) {
                                Log.d(TAG, "Downloaded YouTube thumbnail from: $url")
                                return Base64.encodeToString(optimizedBytes, Base64.NO_WRAP)
                            }
                        }
                    }
                } catch (e: Exception) {
                    Log.w(TAG, "Failed to download thumbnail from $url", e)
                }
            }
            
            Log.w(TAG, "Failed to download any YouTube thumbnail for video: $videoId")
            null
        } catch (e: Exception) {
            Log.e(TAG, "Error downloading YouTube thumbnail", e)
            null
        }
    }
    
    /**
     * Optimizes downloaded image for better performance and storage
     */
    private fun optimizeImage(imageBytes: ByteArray): ByteArray? {
        return try {
            // First decode bounds to compute an inSampleSize
            val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
            BitmapFactory.decodeByteArray(imageBytes, 0, imageBytes.size, bounds)
            val sampleSize = calculateInSampleSize(bounds, MAX_ART_DIMENSION, MAX_ART_DIMENSION)
            
            val options = BitmapFactory.Options().apply {
                inJustDecodeBounds = false
                inSampleSize = sampleSize
                inPreferredConfig = Bitmap.Config.RGB_565 // smaller than ARGB_8888
            }
            
            val bitmap = BitmapFactory.decodeByteArray(imageBytes, 0, imageBytes.size, options)
            if (bitmap != null) {
                val stream = ByteArrayOutputStream(32 * 1024)
                try {
                    bitmap.compress(Bitmap.CompressFormat.JPEG, JPEG_QUALITY, stream)
                } finally {
                    try { bitmap.recycle() } catch (_: Throwable) {}
                }
                stream.toByteArray()
            } else null
        } catch (e: Exception) {
            Log.e(TAG, "Error optimizing image", e)
            null
        }
    }
    
    /**
     * Creates a Song with YouTube metadata and thumbnail
     */
    suspend fun createYouTubeSong(
        videoId: String,
        title: String,
        artist: String,
        filePath: String,
        duration: Long = 0L
    ): Song {
        val thumbnailBase64 = downloadYouTubeThumbnail(videoId)
        
        val song = Song(
            id = filePath.hashCode().toLong(),
            title = title,
            artist = artist,
            album = "YouTube",
            duration = duration,
            path = filePath,
            size = if (!filePath.startsWith("content://")) File(filePath).length() else 0L,
            mimeType = getMimeType(filePath),
            dateAdded = System.currentTimeMillis(),
            albumArt = thumbnailBase64
        )
        
        // Cache the thumbnail for faster future loads
        if (thumbnailBase64 != null) {
            try {
                val cache = com.stash.opusplayer.artwork.ArtworkCache(context)
                val artBytes = Base64.decode(thumbnailBase64, Base64.DEFAULT)
                val outFile = cache.fileFor(song)
                if (!outFile.exists()) {
                    cache.saveJpeg(artBytes, outFile)
                }
            } catch (e: Exception) {
                Log.w(TAG, "Failed to cache YouTube thumbnail", e)
            }
        }
        
        return song
    }
}
