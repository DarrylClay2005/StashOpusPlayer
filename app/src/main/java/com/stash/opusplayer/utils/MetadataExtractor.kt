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
            
            // Extract album art
            val albumArt = extractAlbumArt(retriever)
            
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
    
    private fun extractAlbumArt(retriever: MediaMetadataRetriever): String? {
        return try {
            val artBytes = retriever.embeddedPicture ?: return null
            if (artBytes.isEmpty()) return null

            // First decode bounds to compute an inSampleSize
            val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
            BitmapFactory.decodeByteArray(artBytes, 0, artBytes.size, bounds)
            val sampleSize = calculateInSampleSize(bounds, MAX_ART_DIMENSION, MAX_ART_DIMENSION)

            val options = BitmapFactory.Options().apply {
                inJustDecodeBounds = false
                inSampleSize = sampleSize
                inPreferredConfig = Bitmap.Config.RGB_565 // smaller than ARGB_8888
                inDither = true
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
            // Use NO_WRAP to keep string compact
            Base64.encodeToString(compressedBytes, Base64.NO_WRAP)
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
    
    fun extractBasicInfo(filePath: String): Song? {
        val file = File(filePath)
        if (!file.exists()) return null
        
        val retriever = MediaMetadataRetriever()
        return try {
            retriever.setDataSource(filePath)
            
            val title = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_TITLE) 
                ?: file.nameWithoutExtension
            val artist = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_ARTIST) 
                ?: "Unknown Artist"
            val album = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_ALBUM) 
                ?: "Unknown Album"
            val duration = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)?.toLongOrNull() ?: 0L
            
            Song(
                id = filePath.hashCode().toLong(),
                title = title,
                artist = artist,
                album = album,
                duration = duration,
                path = filePath,
                size = file.length(),
                mimeType = getMimeType(filePath),
                dateAdded = file.lastModified()
            )
        } catch (e: Exception) {
            Log.e(TAG, "Error extracting basic info for $filePath", e)
            null
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
            else -> "audio/*"
        }
    }
}
