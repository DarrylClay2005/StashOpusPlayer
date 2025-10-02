package com.stash.stashwave.utils

import android.content.ContentResolver
import android.content.Context
import android.net.Uri
import java.io.File
import java.io.FileOutputStream

object TagEditor {
    // Embed JPEG artwork into MP3 files using mp3agic. Other formats are not handled.
    fun embedArtworkMp3(context: Context, filePath: String, jpegBytes: ByteArray): Boolean {
        return try {
            if (filePath.startsWith("content://")) {
                // Copy to temp, edit, then write back via SAF
                val resolver: ContentResolver = context.contentResolver
                val uri = Uri.parse(filePath)
                val tempIn = File.createTempFile("mp3_in_", ".mp3", context.cacheDir)
                resolver.openInputStream(uri)?.use { it.copyTo(FileOutputStream(tempIn).buffered()) }
                val tempOut = File.createTempFile("mp3_out_", ".mp3", context.cacheDir)
                val ok = writeMp3WithArt(tempIn.absolutePath, tempOut.absolutePath, jpegBytes)
                if (!ok) return false
                resolver.openOutputStream(uri, "rwt")?.use { os ->
                    tempOut.inputStream().use { ins -> ins.copyTo(os) }
                }
                tempIn.delete()
                tempOut.delete()
                true
            } else {
                val src = File(filePath)
                val tempOut = File.createTempFile("mp3_out_", ".mp3", context.cacheDir)
                val ok = writeMp3WithArt(src.absolutePath, tempOut.absolutePath, jpegBytes)
                if (!ok) return false
                // Replace original
                if (src.canWrite()) {
                    tempOut.copyTo(src, overwrite = true)
                    tempOut.delete()
                    true
                } else {
                    false
                }
            }
        } catch (_: Exception) {
            false
        }
    }

    private fun writeMp3WithArt(inputPath: String, outputPath: String, jpegBytes: ByteArray): Boolean {
        return try {
            val mp3file = com.mpatric.mp3agic.Mp3File(inputPath)
            val id3v2 = if (mp3file.hasId3v2Tag()) mp3file.id3v2Tag else com.mpatric.mp3agic.ID3v24Tag()
            id3v2.setAlbumImage(jpegBytes, "image/jpeg")
            mp3file.id3v2Tag = id3v2
            mp3file.save(outputPath)
            true
        } catch (_: Exception) {
            false
        }
    }
    // Best-effort generic embed using Jaudiotagger (supports many formats)
    fun embedArtworkAny(context: Context, filePath: String, jpegBytes: ByteArray): Boolean {
        return try {
            if (filePath.startsWith("content://")) {
                val resolver = context.contentResolver
                val uri = Uri.parse(filePath)
                val tempIn = File.createTempFile("audio_in_", ".tmp", context.cacheDir)
                resolver.openInputStream(uri)?.use { it.copyTo(FileOutputStream(tempIn).buffered()) }
                val ok = writeArtworkJaudiotagger(tempIn, jpegBytes)
                if (!ok) return false
                resolver.openOutputStream(uri, "rwt")?.use { os ->
                    tempIn.inputStream().use { ins -> ins.copyTo(os) }
                }
                tempIn.delete()
                true
            } else {
                val src = File(filePath)
                if (!src.canWrite()) return false
                writeArtworkJaudiotagger(src, jpegBytes)
            }
        } catch (_: Exception) {
            false
        }
    }

    private fun writeArtworkJaudiotagger(file: File, jpegBytes: ByteArray): Boolean {
        return try {
            val audioFile = org.jaudiotagger.audio.AudioFileIO.read(file)
            val ensuredTag = audioFile.tag ?: run {
                audioFile.createDefaultTag()
                audioFile.tag
            }
            val tag = ensuredTag ?: return false

            // Remove old artwork and add new
            try {
                tag.deleteArtworkField()
            } catch (_: Exception) {
                // ignore
            }

            val art = org.jaudiotagger.tag.datatype.Artwork().apply {
                setBinaryData(jpegBytes)
                setMimeType("image/jpeg")
                setDescription("")
                // Picture type 3 = front cover in ID3 spec
                try { setPictureType(3) } catch (_: Exception) {}
            }
            tag.setField(art)
            org.jaudiotagger.audio.AudioFileIO.write(audioFile)
            true
        } catch (_: Exception) {
            false
        }
    }
}
