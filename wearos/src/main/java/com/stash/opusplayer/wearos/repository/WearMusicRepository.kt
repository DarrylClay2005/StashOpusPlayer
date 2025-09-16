package com.stash.opusplayer.wearos.repository

import android.content.Context
import android.util.Log
import com.google.android.gms.tasks.Tasks
import com.google.android.gms.wearable.*
import com.stash.opusplayer.wearos.data.*
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

class WearMusicRepository private constructor(private val context: Context) {

    companion object {
        private const val TAG = "WearMusicRepository"
        private const val PHONE_CAPABILITY = "stash_opus_player_phone"
        
        @Volatile
        private var INSTANCE: WearMusicRepository? = null
        
        fun getInstance(context: Context): WearMusicRepository {
            return INSTANCE ?: synchronized(this) {
                INSTANCE ?: WearMusicRepository(context.applicationContext).also { INSTANCE = it }
            }
        }
    }

    private val dataClient = Wearable.getDataClient(context)
    private val messageClient = Wearable.getMessageClient(context)
    private val nodeClient = Wearable.getNodeClient(context)
    private val capabilityClient = Wearable.getCapabilityClient(context)

    // State flows for UI observation
    private val _playbackState = MutableStateFlow<WearPlaybackState?>(null)
    val playbackState: StateFlow<WearPlaybackState?> = _playbackState.asStateFlow()

    private val _playlist = MutableStateFlow<WearPlaylist?>(null)
    val playlist: StateFlow<WearPlaylist?> = _playlist.asStateFlow()

    private val _currentSong = MutableStateFlow<WearSong?>(null)
    val currentSong: StateFlow<WearSong?> = _currentSong.asStateFlow()

    private val _isPhoneConnected = MutableStateFlow(false)
    val isPhoneConnected: StateFlow<Boolean> = _isPhoneConnected.asStateFlow()

    init {
        checkPhoneConnection()
    }

    // Update methods called from DataLayerListenerService
    fun updatePlaybackState(state: WearPlaybackState) {
        Log.d(TAG, "Updating playback state: isPlaying=${state.isPlaying}, song=${state.currentSong?.title}")
        _playbackState.value = state
        _currentSong.value = state.currentSong
    }

    fun updatePlaylist(playlist: WearPlaylist) {
        Log.d(TAG, "Updating playlist: ${playlist.songs.size} songs")
        _playlist.value = playlist
    }

    fun updateCurrentSong(song: WearSong) {
        Log.d(TAG, "Updating current song: ${song.title}")
        _currentSong.value = song
    }

    fun updatePhoneConnected(connected: Boolean) {
        Log.d(TAG, "Phone connection status: $connected")
        _isPhoneConnected.value = connected
    }

    // Control methods to send commands to phone
    suspend fun sendPlayCommand(): Boolean {
        return sendControlMessage(WearControlCommands.PLAY)
    }

    suspend fun sendPauseCommand(): Boolean {
        return sendControlMessage(WearControlCommands.PAUSE)
    }

    suspend fun sendNextCommand(): Boolean {
        return sendControlMessage(WearControlCommands.NEXT)
    }

    suspend fun sendPreviousCommand(): Boolean {
        return sendControlMessage(WearControlCommands.PREVIOUS)
    }

    suspend fun sendToggleShuffleCommand(): Boolean {
        return sendControlMessage(WearControlCommands.TOGGLE_SHUFFLE)
    }

    suspend fun sendToggleRepeatCommand(): Boolean {
        return sendControlMessage(WearControlCommands.TOGGLE_REPEAT)
    }

    suspend fun sendSeekToCommand(position: Long): Boolean {
        return sendControlMessage(WearControlCommands.SEEK_TO, "position" to position.toString())
    }

    suspend fun sendPlaySongCommand(songId: Long): Boolean {
        return sendControlMessage(WearControlCommands.PLAY_SONG, "songId" to songId.toString())
    }

    suspend fun sendOpenPhoneAppCommand(): Boolean {
        return sendControlMessage(WearControlCommands.OPEN_PHONE_APP)
    }

    private suspend fun sendControlMessage(command: String, vararg params: Pair<String, String>): Boolean {
        return try {
            val connectedNodes = getConnectedNodes()
            if (connectedNodes.isEmpty()) {
                Log.w(TAG, "No connected nodes to send command: $command")
                return false
            }

            val message = buildString {
                append(command)
                params.forEach { (key, value) ->
                    append("|$key:$value")
                }
            }

            val tasks = connectedNodes.map { node ->
                messageClient.sendMessage(node.id, WearDataPaths.CONTROL_REQUEST, message.toByteArray())
            }

            val results = Tasks.whenAllComplete(tasks).result
            val success = results.all { it.isSuccessful }
            
            Log.d(TAG, "Sent command '$command' to ${connectedNodes.size} nodes, success: $success")
            success
        } catch (e: Exception) {
            Log.e(TAG, "Error sending control message: $command", e)
            false
        }
    }

    private suspend fun getConnectedNodes(): List<Node> {
        return try {
            val capabilityInfo = Tasks.await(capabilityClient.getCapability(PHONE_CAPABILITY, CapabilityClient.FILTER_REACHABLE))
            capabilityInfo.nodes.toList()
        } catch (e: Exception) {
            Log.e(TAG, "Error getting connected nodes", e)
            emptyList()
        }
    }

    private fun checkPhoneConnection() {
        capabilityClient.getCapability(PHONE_CAPABILITY, CapabilityClient.FILTER_REACHABLE)
            .addOnSuccessListener { capabilityInfo ->
                val connectedNodes = capabilityInfo.nodes.filter { it.isNearby }
                updatePhoneConnected(connectedNodes.isNotEmpty())
            }
            .addOnFailureListener { e ->
                Log.e(TAG, "Failed to check phone connection", e)
                updatePhoneConnected(false)
            }
    }

    // Request initial data from phone
    suspend fun requestInitialData(): Boolean {
        return sendControlMessage("REQUEST_INITIAL_DATA")
    }
}
