package com.stash.opusplayer.wearos.data

import android.os.Parcelable
import kotlinx.parcelize.Parcelize

@Parcelize
data class WearSong(
    val id: Long,
    val title: String,
    val artist: String,
    val album: String,
    val duration: Long,
    val artworkUrl: String? = null
) : Parcelable

@Parcelize
data class WearPlaybackState(
    val isPlaying: Boolean,
    val currentSong: WearSong?,
    val position: Long,
    val duration: Long,
    val isShuffling: Boolean,
    val repeatMode: Int, // 0 = OFF, 1 = ALL, 2 = ONE
    val hasNext: Boolean,
    val hasPrevious: Boolean
) : Parcelable

@Parcelize
data class WearPlaylist(
    val songs: List<WearSong>,
    val currentIndex: Int
) : Parcelable

// Data layer path constants
object WearDataPaths {
    const val PLAYBACK_STATE = "/playback_state"
    const val PLAYLIST = "/playlist"
    const val CURRENT_SONG = "/current_song"
    const val CONTROL_REQUEST = "/control_request"
}

// Control commands
object WearControlCommands {
    const val PLAY = "play"
    const val PAUSE = "pause"
    const val NEXT = "next"
    const val PREVIOUS = "previous"
    const val SEEK_TO = "seek_to"
    const val TOGGLE_SHUFFLE = "toggle_shuffle"
    const val TOGGLE_REPEAT = "toggle_repeat"
    const val PLAY_SONG = "play_song"
    const val OPEN_PHONE_APP = "open_phone_app"
}
