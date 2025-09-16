package com.stash.opusplayer.wearos.viewmodel

import android.app.Application
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.stash.opusplayer.wearos.data.WearPlaybackState
import com.stash.opusplayer.wearos.data.WearPlaylist
import com.stash.opusplayer.wearos.data.WearSong
import com.stash.opusplayer.wearos.repository.WearMusicRepository
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.launch

class WearMusicViewModel(application: Application) : AndroidViewModel(application) {

    private val repository = WearMusicRepository.getInstance(application)

    // Expose repository state flows
    val playbackState: StateFlow<WearPlaybackState?> = repository.playbackState
    val playlist: StateFlow<WearPlaylist?> = repository.playlist
    val currentSong: StateFlow<WearSong?> = repository.currentSong
    val isPhoneConnected: StateFlow<Boolean> = repository.isPhoneConnected

    // Control methods
    fun play() {
        viewModelScope.launch {
            repository.sendPlayCommand()
        }
    }

    fun pause() {
        viewModelScope.launch {
            repository.sendPauseCommand()
        }
    }

    fun next() {
        viewModelScope.launch {
            repository.sendNextCommand()
        }
    }

    fun previous() {
        viewModelScope.launch {
            repository.sendPreviousCommand()
        }
    }

    fun toggleShuffle() {
        viewModelScope.launch {
            repository.sendToggleShuffleCommand()
        }
    }

    fun toggleRepeat() {
        viewModelScope.launch {
            repository.sendToggleRepeatCommand()
        }
    }

    fun seekTo(position: Long) {
        viewModelScope.launch {
            repository.sendSeekToCommand(position)
        }
    }

    fun playSong(songId: Long) {
        viewModelScope.launch {
            repository.sendPlaySongCommand(songId)
        }
    }

    fun openPhoneApp() {
        viewModelScope.launch {
            repository.sendOpenPhoneAppCommand()
        }
    }

    fun requestInitialData() {
        viewModelScope.launch {
            repository.requestInitialData()
        }
    }

    // Utility methods
    fun formatTime(milliseconds: Long): String {
        val totalSeconds = milliseconds / 1000
        val minutes = totalSeconds / 60
        val seconds = totalSeconds % 60
        return String.format("%d:%02d", minutes, seconds)
    }

    fun calculateProgress(position: Long, duration: Long): Int {
        return if (duration > 0) {
            ((position * 100) / duration).toInt().coerceIn(0, 100)
        } else 0
    }
}
