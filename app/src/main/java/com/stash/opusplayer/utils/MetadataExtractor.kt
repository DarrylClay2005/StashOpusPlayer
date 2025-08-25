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
    }
    
    fun extractMetadata(song: Song): Song {
        val retriever = MediaMetadataRetriever()
        return try {
            retriever.setDataSource(song.path)
            
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
            val artBytes = retriever.embeddedPicture
            if (artBytes != null && artBytes.isNotEmpty()) {
                // Compress and encode to base64 for storage
                val bitmap = BitmapFactory.decodeByteArray(artBytes, 0, artBytes.size)
                if (bitmap != null) {
                    val stream = ByteArrayOutputStream()
                    bitmap.compress(Bitmap.CompressFormat.JPEG, 80, stream)
                    val compressedBytes = stream.toByteArray()
                    Base64.encodeToString(compressedBytes, Base64.DEFAULT)
                } else null
            } else null
        } catch (e: Exception) {
            Log.e(TAG, "Error extracting album art", e)
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
