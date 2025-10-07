package com.stash.opusplayer.ui

import android.os.Bundle
import androidx.appcompat.app.AppCompatActivity
import androidx.lifecycle.lifecycleScope
import com.stash.opusplayer.R
import kotlinx.coroutines.launch

class MetadataActivity : AppCompatActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_metadata)
        findViewById<android.view.View>(R.id.backButton).setOnClickListener { finish() }
        populate()
    }

    private fun populate() {
        val mgr = (application as com.stash.opusplayer.StashWaveApplication).playerManager
        val current = mgr.currentSong.value
        if (current != null) {
            setText(R.id.fileNameValue, java.io.File(current.path).name)
            setText(R.id.pathValue, current.path)
            setText(R.id.durationValue, "Duration: ${formatTime(current.duration)}")
        }
        lifecycleScope.launch(kotlinx.coroutines.Dispatchers.IO) {
            try {
                val repository = com.stash.opusplayer.data.MusicRepository(this@MetadataActivity)
                val path = current?.path ?: return@launch
                var metadata = repository.metadataDao.getMetadata(path)
                if (metadata == null || isMetadataOutdated(metadata)) {
                    metadata = extractMetadataQuietly(path)
                }
                if (metadata != null) {
                    launch(kotlinx.coroutines.Dispatchers.Main) {
                        setText(R.id.bitrateValue, if (metadata.bitrate > 0) "Bitrate: ${metadata.bitrate / 1000} kbps" else "Bitrate: Unknown")
                        setText(R.id.sampleRateValue, if (metadata.sampleRate > 0) "Sample rate: ${metadata.sampleRate} Hz" else "Sample rate: Unknown")
                        setText(R.id.formatValue, if (metadata.format.isNotBlank()) "Format: ${metadata.format}" else "Format: Unknown")
                    }
                }
            } catch (_: Exception) {}
        }
    }

    private fun setText(id: Int, text: String) {
        findViewById<android.widget.TextView>(id)?.text = text
    }

    private fun isMetadataOutdated(metadata: com.stash.opusplayer.data.MetadataInfo): Boolean {
        val file = java.io.File(metadata.filePath)
        if (!file.exists()) return true
        return file.lastModified() != metadata.lastModified
    }

    private suspend fun extractMetadataQuietly(filePath: String): com.stash.opusplayer.data.MetadataInfo? {
        return try {
            val file = java.io.File(filePath)
            val retriever = android.media.MediaMetadataRetriever()
            try {
                if (filePath.startsWith("content://")) {
                    retriever.setDataSource(this, android.net.Uri.parse(filePath))
                } else {
                    retriever.setDataSource(filePath)
                }
                val bitrate = retriever.extractMetadata(android.media.MediaMetadataRetriever.METADATA_KEY_BITRATE)?.toIntOrNull() ?: 0
                val sampleRate = retriever.extractMetadata(android.media.MediaMetadataRetriever.METADATA_KEY_SAMPLERATE)?.toIntOrNull() ?: 0
                val duration = retriever.extractMetadata(android.media.MediaMetadataRetriever.METADATA_KEY_DURATION)?.toLongOrNull() ?: 0L
                val mimeType = retriever.extractMetadata(android.media.MediaMetadataRetriever.METADATA_KEY_MIMETYPE) ?: ""
                val format = when {
                    mimeType.contains("mp3", true) -> "MP3"
                    mimeType.contains("flac", true) -> "FLAC"
                    mimeType.contains("opus", true) -> "Opus"
                    mimeType.contains("ogg", true) -> "OGG"
                    mimeType.contains("m4a", true) || mimeType.contains("mp4", true) -> "M4A"
                    mimeType.contains("wav", true) -> "WAV"
                    mimeType.contains("wma", true) -> "WMA"
                    else -> filePath.substringAfterLast('.', "Unknown").uppercase()
                }
                val metadata = com.stash.opusplayer.data.MetadataInfo(
                    filePath = filePath,
                    fileName = file.name,
                    duration = duration,
                    bitrate = bitrate,
                    sampleRate = sampleRate,
                    format = format,
                    mimeType = mimeType,
                    fileSize = if (file.exists()) file.length() else 0L,
                    lastModified = if (file.exists()) file.lastModified() else 0L,
                    hasErrors = false
                )
                val repository = com.stash.opusplayer.data.MusicRepository(this)
                repository.metadataDao.insertMetadata(metadata)
                metadata
            } finally { retriever.release() }
        } catch (_: Exception) { null }
    }

    private fun formatTime(milliseconds: Long): String {
        val minutes = java.util.concurrent.TimeUnit.MILLISECONDS.toMinutes(milliseconds)
        val seconds = java.util.concurrent.TimeUnit.MILLISECONDS.toSeconds(milliseconds) -
                java.util.concurrent.TimeUnit.MINUTES.toSeconds(minutes)
        return String.format("%d:%02d", minutes, seconds)
    }
}
