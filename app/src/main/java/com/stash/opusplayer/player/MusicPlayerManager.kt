package com.stash.stashwave.player

import android.content.ComponentName
import android.content.Context
import androidx.media3.common.MediaItem
import androidx.media3.common.MediaMetadata
import androidx.media3.common.Player
import androidx.media3.session.MediaController
import androidx.media3.session.SessionToken
import com.google.common.util.concurrent.ListenableFuture
import com.google.common.util.concurrent.MoreExecutors
import com.stash.stashwave.audio.EqualizerManager
import com.stash.stashwave.data.Song
import com.stash.stashwave.service.MusicService
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import android.media.AudioManager
import android.os.Handler
import android.os.Looper

class MusicPlayerManager(private val context: Context) {
    
    private var controllerFuture: ListenableFuture<MediaController>? = null
    private var mediaController: MediaController? = null

    // Queue actions invoked before controller is ready
    private val pendingControllerActions = mutableListOf<(MediaController) -> Unit>()
    
    private val _currentSong = MutableStateFlow<Song?>(null)
    val currentSong: StateFlow<Song?> = _currentSong.asStateFlow()
    
    private val _isPlaying = MutableStateFlow(false)
    val isPlaying: StateFlow<Boolean> = _isPlaying.asStateFlow()
    
    private val _currentPosition = MutableStateFlow(0L)
    val currentPosition: StateFlow<Long> = _currentPosition.asStateFlow()
    
    private val _playbackState = MutableStateFlow(Player.STATE_IDLE)
    val playbackState: StateFlow<Int> = _playbackState.asStateFlow()
    
    private val _playlist = MutableStateFlow<List<Song>>(emptyList())
    val playlist: StateFlow<List<Song>> = _playlist.asStateFlow()
    
    private val _currentIndex = MutableStateFlow(0)
    val currentIndex: StateFlow<Int> = _currentIndex.asStateFlow()
    
    // Original playlist order (before shuffle)
    
    private val _repeatMode = MutableStateFlow(Player.REPEAT_MODE_OFF)
    val repeatMode: StateFlow<Int> = _repeatMode.asStateFlow()
    
    private val playerListener = object : Player.Listener {
        override fun onPlaybackStateChanged(playbackState: Int) {
            _playbackState.value = playbackState
        }
        
        override fun onIsPlayingChanged(isPlaying: Boolean) {
            _isPlaying.value = isPlaying
        }
        
            override fun onMediaItemTransition(mediaItem: MediaItem?, reason: Int) {
                updateCurrentSong()
            }
        
        override fun onRepeatModeChanged(repeatMode: Int) {
            _repeatMode.value = repeatMode
        }
    }
    
    fun initialize() {
        val sessionToken = SessionToken(context, ComponentName(context, MusicService::class.java))
        controllerFuture = MediaController.Builder(context, sessionToken).buildAsync()
        controllerFuture?.addListener({
            mediaController = controllerFuture?.get()
            mediaController?.addListener(playerListener)
            // Flush any queued actions
            mediaController?.let { controller ->
                val iterator = pendingControllerActions.iterator()
                while (iterator.hasNext()) {
                    try {
                        iterator.next().invoke(controller)
                    } catch (_: Exception) {}
                    iterator.remove()
                }
            }
        }, MoreExecutors.directExecutor())
    }
    
    fun release() {
        mediaController?.removeListener(playerListener)
        controllerFuture?.let { MediaController.releaseFuture(it) }
    }
    
    // Playback control methods
    fun play() { runWhenReady { it.play() } }
    
    fun pause() { runWhenReady { it.pause() } }
    
    fun stop() { runWhenReady { it.stop() } }
    
    fun seekTo(position: Long) { runWhenReady { it.seekTo(position) } }
    
    fun skipToNext() {
        runWhenReady { it.seekToNext() }
    }
    
    fun skipToPrevious() {
        runWhenReady { it.seekToPrevious() }
    }
    
    
    fun setRepeatMode(repeatMode: Int) {
        runWhenReady { it.repeatMode = repeatMode }
        _repeatMode.value = repeatMode
    }
    
    // Playlist management
    fun playSong(song: Song) {
        setPlaylist(listOf(song))
        playFromPlaylist(0)
    }
    
    fun setPlaylist(songs: List<Song>) {
        _playlist.value = songs
        val mediaItems = songs.map { song -> createMediaItem(song) }
        runWhenReady { it.setMediaItems(mediaItems) }
    }

    // Atomically replace the queue and start playing from index
    fun playQueue(songs: List<Song>, startIndex: Int) {
        if (songs.isEmpty()) return
        val idx = startIndex.coerceIn(0, songs.lastIndex)
        _playlist.value = songs
        _currentIndex.value = idx
        _currentSong.value = songs[idx]
        val mediaItems = songs.map { song -> createMediaItem(song) }
        runWhenReady {
            try {
                it.setMediaItems(mediaItems, idx, /* startPositionMs= */ 0)
            } catch (_: Exception) {
                // Fallback if overloaded method not available
                it.setMediaItems(mediaItems)
                it.seekToDefaultPosition(idx)
            }
            it.prepare()
            it.play()
        }
    }
    
    fun addToPlaylist(song: Song) {
        val currentPlaylist = _playlist.value.toMutableList()
        currentPlaylist.add(song)
        _playlist.value = currentPlaylist
        
        val mediaItem = createMediaItem(song)
        runWhenReady { it.addMediaItem(mediaItem) }
    }
    
    fun removeFromPlaylist(index: Int) {
        if (index >= 0 && index < _playlist.value.size) {
            val currentPlaylist = _playlist.value.toMutableList()
            currentPlaylist.removeAt(index)
            _playlist.value = currentPlaylist
            
            runWhenReady { it.removeMediaItem(index) }
        }
    }
    
    fun playFromPlaylist(index: Int) {
        if (index >= 0 && index < _playlist.value.size) {
            _currentIndex.value = index
            _currentSong.value = _playlist.value[index]
            runWhenReady {
                it.seekToDefaultPosition(index)
                it.prepare()
                it.play()
            }
        }
    }
    
    // Helper methods
    private fun createMediaItem(song: Song): MediaItem {
        val metaBuilder = MediaMetadata.Builder()
            .setTitle(song.displayName)
            .setArtist(song.artistName)
            .setAlbumTitle(song.albumName)
        // Provide artwork to the system media controls if embedded art is available
        try {
            if (!song.albumArt.isNullOrEmpty()) {
                val bytes = android.util.Base64.decode(song.albumArt, android.util.Base64.DEFAULT)
                if (bytes != null && bytes.isNotEmpty()) {
                    metaBuilder.setArtworkData(bytes, "image/jpeg")
                }
            }
        } catch (_: Exception) {}
        val metadata = metaBuilder.build()
        
        val uri = resolveSongUri(song)
        return MediaItem.Builder()
            .setUri(uri)
            .setMediaMetadata(metadata)
            .build()
    }
    
    private fun resolveSongUri(song: Song): android.net.Uri {
        // Prefer explicit content URIs and verified file paths; only fall back to MediaStore by ID
        return try {
            val path = song.path
            // 1) If it's already a content URI, use it as-is
            if (path.startsWith("content://")) {
                return android.net.Uri.parse(path)
            }
            // 2) If the underlying file exists, play from file path
            val file = java.io.File(path)
            if (file.exists()) {
                return android.net.Uri.fromFile(file)
            }
            // 3) As a last resort, if we have a MediaStore ID, build a content URI
            if (song.id > 0L) {
                return android.content.ContentUris.withAppendedId(
                    android.provider.MediaStore.Audio.Media.EXTERNAL_CONTENT_URI,
                    song.id
                )
            }
            // 4) Fallback to parsing whatever we have
            android.net.Uri.parse(path)
        } catch (_: Exception) {
            // Fallback to parsing the raw path
            android.net.Uri.parse(song.path)
        }
    }
    
    private fun updateCurrentSong() {
        val controller = mediaController ?: return
        val idx = controller.currentMediaItemIndex
        val list = _playlist.value
        if (idx >= 0 && idx < list.size) {
            _currentIndex.value = idx
            _currentSong.value = list[idx]
        } else {
            // Fallback from controller metadata so UI updates even without local playlist mirror
            val mm = controller.mediaMetadata
            val fallback = com.stash.stashwave.data.Song(
                id = 0L,
                title = mm.title?.toString() ?: "",
                artist = mm.artist?.toString() ?: "",
                album = mm.albumTitle?.toString() ?: "",
                duration = controller.duration.takeIf { it > 0 } ?: 0L,
                path = ""
            )
            _currentSong.value = fallback
        }
    }
    
    // Position tracking (call this periodically)
    fun updatePosition() {
        mediaController?.let { controller ->
            _currentPosition.value = controller.currentPosition
        }
    }
    
    private fun runWhenReady(action: (MediaController) -> Unit) {
        val controller = mediaController
        if (controller != null) {
            action(controller)
        } else {
            pendingControllerActions.add(action)
        }
    }
    
    // Shuffle helper methods
    
    // Fast forward functionality (skip 30 seconds)
    fun fastForward() {
        val currentPos = getCurrentPosition()
        val duration = getDuration()
        if (duration > 0) {
            val newPos = (currentPos + 30000).coerceAtMost(duration)
            seekTo(newPos)
        }
    }
    
    // Rewind functionality (skip back 10 seconds)
    fun rewind() {
        val currentPos = getCurrentPosition()
        val newPos = (currentPos - 10000).coerceAtLeast(0L)
        seekTo(newPos)
    }

    // Get current playback info
    fun getCurrentPosition(): Long = mediaController?.currentPosition ?: 0L
    fun getDuration(): Long = mediaController?.duration ?: 0L
    fun getBufferedPosition(): Long = mediaController?.bufferedPosition ?: 0L
}
