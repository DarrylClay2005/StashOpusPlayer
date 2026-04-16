package com.stash.opusplayer.utils

import android.content.ContentResolver
import android.content.Context
import android.net.Uri
import android.util.Log
import java.io.File
import java.io.FileOutputStream

object FfmpegEmbedder {
    private const val TAG = "FfmpegEmbedder"

    fun isAvailable(): Boolean {
        return try {
            Class.forName("com.arthenica.ffmpegkit.FFmpegKit")
            true
        } catch (_: Throwable) {
            false
        }
    }

    fun embedArtwork(context: Context, filePath: String, jpegBytes: ByteArray): Boolean {
        return try {
            val isContent = filePath.startsWith("content://")
            val resolver: ContentResolver? = if (isContent) context.contentResolver else null
            val uri: Uri? = if (isContent) Uri.parse(filePath) else null

            // Prepare temp cover file
            val coverFile = File.createTempFile("cover_", ".jpg", context.cacheDir)
            FileOutputStream(coverFile).use { it.write(jpegBytes) }

            // Prepare input and output temp files
            val extension = filePath.substringAfterLast('.', "").lowercase()
            val inFile: File = if (isContent) {
                val tmp = File.createTempFile("in_", ".$extension", context.cacheDir)
                val inputUri = uri ?: return false
                val inputStream = resolver?.openInputStream(inputUri) ?: return false
                inputStream.use { stream ->
                    tmp.outputStream().use { output -> stream.copyTo(output) }
                }
                tmp
            } else {
                File(filePath)
            }
            val outFile = File.createTempFile("out_", ".$extension", context.cacheDir)

            val cmd = buildFfmpegCommand(inFile, coverFile, outFile, extension)
            Log.d(TAG, "FFmpeg cmd: $cmd")
            val success = executeFfmpeg(cmd)
            if (success) {
                if (isContent) {
                    val outputUri = uri ?: return false
                    val outputStream = resolver?.openOutputStream(outputUri, "rwt") ?: return false
                    outputStream.use { os ->
                        outFile.inputStream().use { ins -> ins.copyTo(os) }
                    }
                } else {
                    // Replace original file
                    try {
                        outFile.copyTo(inFile, overwrite = true)
                    } catch (e: Exception) {
                        Log.w(TAG, "Failed to replace original with ffmpeg output", e)
                        return false
                    }
                }
            } else {
                Log.w(TAG, "FFmpeg embedding failed or unavailable")
            }

            // Cleanup
            try { coverFile.delete() } catch (_: Throwable) {}
            if (isContent) try { inFile.delete() } catch (_: Throwable) {}
            try { outFile.delete() } catch (_: Throwable) {}

            success
        } catch (e: Exception) {
            Log.e(TAG, "embedArtwork error", e)
            false
        }
    }

    private fun executeFfmpeg(cmd: String): Boolean {
        return try {
            val kitCls = Class.forName("com.arthenica.ffmpegkit.FFmpegKit")
            val exec = kitCls.getMethod("execute", String::class.java)
            val session = exec.invoke(null, cmd)
            val rc = session.javaClass.getMethod("getReturnCode").invoke(session)
            val rcCls = Class.forName("com.arthenica.ffmpegkit.ReturnCode")
            val isSuccess = rcCls.getMethod("isValueSuccess", rcCls).invoke(null, rc) as Boolean
            isSuccess
        } catch (e: Throwable) {
            Log.w(TAG, "FFmpeg not available or failed: ${e.message}")
            false
        }
    }

    private fun buildFfmpegCommand(inFile: File, coverFile: File, outFile: File, ext: String): String {
        val input = inFile.absolutePath
        val cover = coverFile.absolutePath
        val output = outFile.absolutePath
        return when (ext) {
            "mp3" -> {
                "-y -i \"$input\" -i \"$cover\" -map 0:a -map 1 -c:a copy -c:v mjpeg -id3v2_version 3 -metadata:s:v title=\"Album cover\" -metadata:s:v comment=\"Cover (front)\" -disposition:v:0 attached_pic \"$output\""
            }
            "m4a", "mp4", "aac" -> {
                "-y -i \"$input\" -i \"$cover\" -map 0:a -map 1 -c:a copy -c:v mjpeg -metadata:s:v title=\"Album cover\" -metadata:s:v comment=\"Cover (front)\" -disposition:v:0 attached_pic \"$output\""
            }
            "opus", "ogg" -> {
                // Attempt using attached_pic; may not be universally honored for opus/ogg
                "-y -i \"$input\" -i \"$cover\" -map 0:a -map 1 -c:a copy -c:v mjpeg -metadata:s:v title=\"Album cover\" -disposition:v:0 attached_pic \"$output\""
            }
            else -> {
                // Default behavior
                "-y -i \"$input\" -i \"$cover\" -map 0:a -map 1 -c:a copy -c:v mjpeg -metadata:s:v title=\"Album cover\" -disposition:v:0 attached_pic \"$output\""
            }
        }
    }
}
