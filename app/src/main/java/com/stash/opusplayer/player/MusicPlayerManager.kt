package com.stash.opusplayer.player

import android.content.ComponentName
import android.content.Context
import androidx.media3.common.MediaItem
import androidx.media3.common.MediaMetadata
import androidx.media3.common.Player
import androidx.media3.session.MediaController
import androidx.media3.session.SessionToken
import com.google.common.util.concurrent.ListenableFuture
import com.google.common.util.concurrent.MoreExecutors
import com.stash.opusplayer.audio.EqualizerManager
import com.stash.opusplayer.data.Song
import com.stash.opusplayer.service.MusicService
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
    
    private val _shuffleMode = MutableStateFlow(false)
    val shuffleMode: StateFlow<Boolean> = _shuffleMode.asStateFlow()
    
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
        
        override fun onShuffleModeEnabledChanged(shuffleModeEnabled: Boolean) {
            _shuffleMode.value = shuffleModeEnabled
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
        val currentIndex = _currentIndex.value
        val playlist = _playlist.value
        
        if (currentIndex < playlist.size - 1) {
            playFromPlaylist(currentIndex + 1)
        } else if (_repeatMode.value == Player.REPEAT_MODE_ALL) {
            playFromPlaylist(0)
        }
    }
    
    fun skipToPrevious() {
        val currentIndex = _currentIndex.value
        
        if (currentIndex > 0) {
            playFromPlaylist(currentIndex - 1)
        } else if (_repeatMode.value == Player.REPEAT_MODE_ALL) {
            playFromPlaylist(_playlist.value.size - 1)
        }
    }
    
    fun toggleShuffle() {
        val enabled = !_shuffleMode.value
        runWhenReady { it.shuffleModeEnabled = enabled }
        _shuffleMode.value = enabled
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
        val metadata = MediaMetadata.Builder()
            .setTitle(song.displayName)
            .setArtist(song.artistName)
            .setAlbumTitle(song.albumName)
            .build()
        
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
        val currentIndex = mediaController?.currentMediaItemIndex ?: 0
        if (currentIndex >= 0 && currentIndex < _playlist.value.size) {
            _currentIndex.value = currentIndex
            _currentSong.value = _playlist.value[currentIndex]
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
    
    // Get current playback info
    fun getCurrentPosition(): Long = mediaController?.currentPosition ?: 0L
    fun getDuration(): Long = mediaController?.duration ?: 0L
    fun getBufferedPosition(): Long = mediaController?.bufferedPosition ?: 0L
}
